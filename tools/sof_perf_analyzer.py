#!/usr/bin/env python3

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2023 Intel Corporation. All rights reserved.

'''
The sof_perf_analyzer helps to analyze SOF trace output generated during the running of
aplay and arecord commands or a test case in sof-test repository. It takes human readable
trace file (contents from plain mtrace or the decoded dictionary trace) as input, and
output below analysis results:
    - Average and maximum MCPS of cpu average and cpu peak per SOF audio component

Example of performance logging:
[    4.612041] <inf> component: comp_copy: comp:1 0x40001 perf comp_copy samples 48 period
 1000 cpu avg 459 peak 473

There is no audio component name information in SOF trace, so auxiliary linux kernel log
is used to extract component name.
'''

import re
import pathlib
import argparse
from datetime import timedelta
from typing import TextIO
from typing import Generator
from dataclasses import dataclass

import pandas as pd

# CPC_MARGIN is set to 1.5, because there is some inactive code for some module
# due to unmet condition. For example:
# volume: ramp operation only run on volume change, but we don't do volume
# change in our test.

# So, we set a relative high margin for avg cycles.
# CPC = AVG(module) * CPC_MARGIN
CPC_MARGIN = 1.5

@dataclass()
class TraceItem:
    '''The structural representation for a single, parsed line of trace'''
    timestamp: float
    level: str
    context: str # the trace context registered with LOG_MODULE_REGISTER
    func: str
    # The user message filled to log functions, exclude timestamp, log level,
    # log context and log function, which is prepended by zephyr logging system
    msg: str

@dataclass(frozen=True)
class Component:
    '''The identifier for a SOF audio component'''
    ppln_id: str
    comp_id: int

    def __str__(self) -> str:
        return f'{self.ppln_id}-{self.comp_id:#08x}'

PERF_INFO_COL = ['COMP_ID', 'TIMESTAMP', 'SAMPLES', 'PERIOD', 'CPU_AVG', 'CPU_PEAK']

# pylint: disable=C0103
args = None

perf_info: pd.DataFrame = pd.DataFrame(
        columns=PERF_INFO_COL
    )

perf_stats: pd.DataFrame | None = None

TraceItemGenerator = Generator[TraceItem, None, None]

def collect_perf_info(trace_item: TraceItem):
    '''Parse and collect performace trace information(msg field of TraceItem) to
    pandas DataFrame for further analysis.
    '''
    msg = trace_item.msg.split()
    ppln_id = msg[0].split(':')[1]
    comp_id = int(msg[1], 16)

    row_data = pd.Series(
        dict(zip(PERF_INFO_COL,
                [str(Component(ppln_id, comp_id)),  trace_item.timestamp,
                 int(msg[5]), int(msg[7]), int(msg[10]), int(msg[12])]
            )
        )
    )
    # pylint: disable=W0603
    global perf_info
    perf_info = pd.concat([perf_info, row_data.to_frame().T], ignore_index=True)

def dispatch_trace_item(trace_item: TraceItem):
    '''Dispatch trace item to cosponding trace collecting function. In a TraceItem,
    we have log timestamp, log level, log context and log function, with them, dispatch
    could be easily implemented.
    '''
    if trace_item.func == 'comp_copy':
        collect_perf_info(trace_item)

def skip_to_first_trace(trace_item_gen: TraceItemGenerator):
    '''The current sof-test test case may collect some traces belonging to previous
    test case due to mtrace is configured in deferred mode. This function consumes
    those traces from the generator, and return the first trace item of current test.
    '''
    while item := next(trace_item_gen):
        # On test running, the SOF firmware is reloaded to DSP, timer is reset to 0.
        # The first trace must have a timestamp with integral part equals to 0.
        if int(item.timestamp) == 0:
            return item
    return next(trace_item_gen)

def make_trace_item(fileio: TextIO) -> TraceItemGenerator:
    '''Filter and parse a line of trace in string form into TraceItem object, for example:
    '[    2.566046] <inf> component: comp_copy: comp:0 0x40000 perf comp_copy samples
    48 period 1000 cpu avg 413 peak 425' -> TraceItem(timestamp=2.566046, level='inf',
    context='component', func='comp_cppy', msg='comp:0 0x40000 perf comp_copy samples
    48 period 1000 cpu avg 413 peak 425')

    In this function, we do the first stage filtering and parsing. The firmware trace file
    contains some information that is not quite formated, for example:
    '*** Booting Zephyr OS build v3.4.0-rc2 ***', those messages are and dropped. Other messages
    with timestamp, log level, log context, log function are parsed to a TraceItem for timestamp
    correction and second stage filtering and parsing.
    '''
    for line in fileio:
        # Filter extra lines that are not formal traces, for example, the banner,
        # which don't contain timestamp and trace level.
        if match_obj := re.search(r'\[.+\] <(dbg|inf|wrn|err)>', line):
            # Sometimes, A trace output may be incomplete and mixed with next
            # trace output in a single line, for example: '[    0.071590] <inf>
            # pipe[    0.071751] <inf> host_comp: host_get_copy_bytes_normal: comp:1
            # 0x40003 no bytes to copy, available samples: 0, free_samples: 384'.
            # Under this circumstance, we ignore the first trace and extract the
            # second trace from the line. This is done by regarding the end position
            # of the matched substring as sentinel, timestamp and trace level are
            # both some specific offset from the sentinel.
            span_end_pos = match_obj.span()[1]
            trace_lvl = line[span_end_pos - 4: span_end_pos - 1]
            try:
                timestamp = float(line[span_end_pos - 19: span_end_pos - 7].strip())
            # Support for CONFIG_LOG_OUTPUT_FORMAT_TIME_TIMESTAMP - For when default Zephyr timestamp format is used
            except ValueError:
                h, m, rest = line[span_end_pos - 23: span_end_pos - 7].strip().split(':')
                s1, s2 = rest.split(',')
                s = s1+s2
                timestamp = timedelta(
                    hours=int(h),
                    minutes=int(m),
                    seconds=float(s)
                ).total_seconds()

            # The rest after removing timestamp and log level
            rest = line[span_end_pos + 1:].split(': ')
            ctx, func = rest[0:2]
            msg = ': '.join(rest[2:]).strip()
            yield TraceItem(timestamp, trace_lvl, ctx, func, msg)

def process_trace_file():
    '''The top-level caller for processing the trace file'''
    dsp_timer = 38400000
    uint32_max = 4294967295
    # Once DSP timer count to UINT32_MAX, it wrapped to zero, which causes
    # the timestamp wrap to zero, too. This ts_shift is used to correct
    # the timestamp value on wrap. UINT32_MAX / DSP_TIMER is added to it at
    # every wrap.
    #
    # pylint: disable=C0103
    ts_shift = 0
    with open(args.filename, 'r', encoding='utf8') as file:
        trace_item_gen = make_trace_item(file)
        trace_prev = None
        try:
            if args.skip_to_first_trace:
                trace_prev = skip_to_first_trace(trace_item_gen)
            else:
                trace_prev = next(trace_item_gen)
        except StopIteration as si:
            si.args = ('No valid trace in provided file',)
            raise
        for trace_curr in trace_item_gen:
            # pylint: disable=W0603
            old_ts_shift = ts_shift
            # On wrap happened, the timestamp of current trace should be much more smaller
            # than the previous one. In practice, it is possible that the timestamp of
            # current trace is slightly smaller than the previous one, this could be a
            # bug in SOF. Add a 50s shift to make sure timestamp correction work properly.
            if trace_curr.timestamp < trace_prev.timestamp - 50:
                ts_shift = ts_shift + uint32_max / dsp_timer
            trace_prev.timestamp += old_ts_shift
            dispatch_trace_item(trace_prev)
            trace_prev = trace_curr
        trace_prev.timestamp += ts_shift
        dispatch_trace_item(trace_prev)

def process_kmsg_file():
    '''Process the dmesg to get the component ID to component name mapping,
    they are acquired from the line that contains 'Create widget':
        [   59.622645] snd_sof:sof_ipc4_widget_setup: sof-audio-pci-intel-mtl 0000:00:1f.3:
        Create widget host-copier.0.capture (pipe 3) - ID 4, instance 3, core 0"

    By design in the kernel, pipeline ID is the instance ID of pipeline
    widget, so it is acquired from the line that contains 'Create pipeline':
        [   59.622134] snd_sof:sof_ipc4_widget_setup: sof-audio-pci-intel-mtl 0000:00:1f.3:
        Create pipeline pipeline.3 (pipe 3) - instance 3, core 0

    In practice, sof-test only capture kernel message and firmware trace generated during a test
    case run. Mostly in manual tests, if the kernel message file contains multiple firmware runs
    with overlapping information, the last one wins.
    '''
    comp_name = {}
    with open(args.kmsg, encoding='utf8') as f:
        ppln_id = None
        for line in f:
            if match_obj := re.search(r"Create (widget|pipeline)", line):
                span_end_pos = match_obj.span()[1]
                line_split = line[span_end_pos + 1:].split()
                widget_name = line_split[0]
                # In the linux kernel, IDA is used to allocated pipeline widget instance ID,
                # this ID later is used for pipeline creation, thus becomes pipeline ID in the
                # firmware. Note that ppln_id variable will be assigned properly at pipeline widget
                # creation, because it is always the first one to be created before all other
                # widgets in the same pipeline and pipelines are created sequentially.
                if widget_name.startswith('pipeline'):
                    # remove ending comma(,) with [:-1]
                    ppln_id = int(line_split[5][:-1])
                    continue
                # remove ending comma(,) with [:-1]
                module_instance_id = int(line_split[7][:-1])
                # remove ending comma(,) with [:-1]
                widget_id = int(line_split[5][:-1])
                # final module id are composed with high16(module instance id) + low16(module id)
                widget_id |= module_instance_id << 16
                comp_name[str(Component(ppln_id, widget_id))] = widget_name

    col_data = pd.DataFrame(
        comp_name.values(),
        index=comp_name.keys(),
        columns=['COMP_NAME']
    )
    # pylint: disable=W0603
    global perf_stats
    perf_stats = perf_stats.join(col_data, how='left')

    # Move COMP_NAME column as the first column
    perf_stats = pd.concat([perf_stats.iloc[:,-1], perf_stats.iloc[:,0:-1]], axis=1)

def analyze_perf_info():
    '''Calculate performance statistics from performance information'''
    perf_info['CPU_AVG_MCPS'] = perf_info['CPU_AVG'] / perf_info['PERIOD']
    perf_info['CPU_PEAK_MCPS'] = perf_info['CPU_PEAK'] / perf_info['PERIOD']
    # pylint: disable=W0603
    global perf_stats
    perf_stats = pd.concat([
        perf_info.groupby('COMP_ID')['CPU_AVG_MCPS'].min(),
        perf_info.groupby('COMP_ID')['CPU_AVG_MCPS'].mean(),
        perf_info.groupby('COMP_ID')['CPU_AVG_MCPS'].max(),
        perf_info.groupby('COMP_ID')['CPU_PEAK_MCPS'].min(),
        perf_info.groupby('COMP_ID')['CPU_PEAK_MCPS'].mean(),
        perf_info.groupby('COMP_ID')['CPU_PEAK_MCPS'].max()
        ], axis=1
    )
    perf_stats.columns = ['CPU_AVG(MIN)', 'CPU_AVG(AVG)', 'CPU_AVG(MAX)',
                          'CPU_PEAK(MIN)', 'CPU_PEAK(AVG)', 'CPU_PEAK(MAX)']
    perf_stats['PEAK(MAX)/AVG(AVG)'] = perf_stats['CPU_PEAK(MAX)'] / perf_stats['CPU_AVG(AVG)']
    perf_stats['MODULE_CPC'] = perf_info.groupby('COMP_ID')['CPU_AVG'].mean() * CPC_MARGIN
    # change data type from float to int
    perf_stats['MODULE_CPC'] = perf_stats['MODULE_CPC'].astype(int)

def print_perf_info():
    '''Output SOF performance info'''
    stats = perf_stats.rename_axis('COMP_ID').reset_index()
    # pylint: disable=C0209
    with pd.option_context('display.float_format', '{:0.3f}'.format,
                           'display.max_rows', None,
                           'display.max_columns', None):
        print(stats)

    if args.out2csv is not None:
        stats.to_csv(args.out2csv, sep=',', float_format='{:.3f}'.format, index=False)

    if args.out2html is not None:
        stats.to_html(args.out2html, float_format='{:.3f}'.format, index=False)

def parse_args():
    '''Parse command line arguments'''
    parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter,
                                     description=__doc__)
    parser.add_argument('filename')
    parser.add_argument('--kmsg', type=pathlib.Path, required=False,
                        help='Kernel message file captured with journalctl or other log utility')
    parser.add_argument('--out2csv', type=pathlib.Path, required=False,
                    help='Output SOF performance statistics to csv file')
    parser.add_argument('--out2html', type=pathlib.Path, required=False,
                    help='Output SOF performance statistics to html file')
    parser.add_argument('-s', '--skip-to-first-trace', action="store_true",  default=False,
                        help='''In CI test, some traces from previous test case will appear in
the mtrace of current test case, this flag is used to denote if we
want to skip until the first line with a timestamp between 0 and 1s.
For CI test, set the flag to True''')

    return parser.parse_args()

def main():
    '''The main entry'''
    # pylint: disable=W0603
    global args
    args = parse_args()

    process_trace_file()

    analyze_perf_info()

    if args.kmsg is not None:
        process_kmsg_file()

    print_perf_info()

if __name__ == "__main__":
    main()
