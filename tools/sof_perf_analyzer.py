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

Hardcoded value explained:
DSP_CLK: The DSP clock frequency in Hz.
DSP_TIMER: The DSP timer clock frequency in Hz.
'''

import re
import pathlib
import argparse
from typing import TextIO
from typing import Generator
from dataclasses import dataclass

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

@dataclass(frozen=True)
class CompPerfSample:
    '''The dataclass for SOF audio component performance info'''
    timestamp: float
    samples: int
    period: int
    cpu_avg: int
    cpu_peak: int

@dataclass(frozen=True)
class CompPerfStats:
    '''The dataclass for SOF audio component statistics'''
    avg_cpu_avg: float  # average of cpu average
    max_cpu_avg: float  # maximum of cpu average
    min_cpu_avg: float  # minimum of cpu average
    avg_cpu_peak: float # average of cpu peak
    max_cpu_peak: float # maximum of cpu peak
    min_cpu_peak: float # minimum of cpu peak

# Currently, we don't have test case to test low-power mode, in which
# the DSP may not operate in the maximum clock frequency. Let't hardcode
# this value to the maximum clock frequency for now.
DSP_CLK = 400000000
# The DSP timer clock frequency is fixed despite of DSP_CLK
DSP_TIMER = 38400000
UINT32_MAX = 4294967295
AUDIO_PERIOD = 1000

TICK_TO_MCPS = DSP_CLK / DSP_TIMER / AUDIO_PERIOD

# Once DSP timer count to UINT32_MAX, it wrapped to zero, which causes
# the timestamp wrap to zero, too. This ts_shift is used to correct
# the timestamp value on wrap. UINT32_MAX / DSP_TIMER is added to it at
# every wrap.
#
# pylint: disable=C0103
ts_shift = 0
# pylint: disable=C0103
args = None

# This map gives access to the list of component performance samples
# collected for a given component
perf_info: dict[Component, list[CompPerfSample]] = {}
perf_stats: dict[Component, CompPerfStats] = {}
component_name: dict[Component, str] = {}

TraceItemGenerator = Generator[TraceItem, None, None]

def collect_perf_info(trace_item: TraceItem):
    '''Parse and collect performace trace information(msg field of TraceItem) to a
    Component->list[CompPerfSample] mapping for further analysis.
    '''
    msg = trace_item.msg.split()
    ppln_id = msg[0].split(':')[1]
    comp_id = int(msg[1], 16)
    perf_val = int(msg[5]), int(msg[7]), int(msg[10]), int(msg[12])
    perf_sample = CompPerfSample(trace_item.timestamp, *perf_val)
    comp_perf_info_list = perf_info.setdefault(Component(ppln_id, comp_id), [])
    comp_perf_info_list.append(perf_sample)

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
            timestamp = float(line[span_end_pos - 19: span_end_pos - 7].strip())

            # The rest after removing timestamp and log level
            rest = line[span_end_pos + 1:].split(': ')
            ctx, func = rest[0:2]
            msg = ': '.join(rest[2:]).strip()
            yield TraceItem(timestamp, trace_lvl, ctx, func, msg)

def process_trace_file():
    '''The top-level caller for processing the trace file'''
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
            global ts_shift
            old_ts_shift = ts_shift
            # On wrap happened, the timestamp of current trace should be much more smaller
            # than the previous one. In practice, it is possible that the timestamp of
            # current trace is slightly smaller than the previous one, this could be a
            # bug in SOF. Add a 50s shift to make sure timestamp correction work properly.
            if trace_curr.timestamp < trace_prev.timestamp - 50:
                ts_shift = ts_shift + UINT32_MAX / DSP_TIMER
            trace_prev.timestamp += old_ts_shift
            dispatch_trace_item(trace_prev)
            trace_prev = trace_curr
        trace_prev.timestamp += ts_shift
        dispatch_trace_item(trace_prev)

def process_kmsg_file():
    '''Process the dmesg to get the component ID to component name mapping,
    component name is acquired from the line that contains 'Create widget',
    component ID is acquired from the next line. Example:
    [  334.818435] kernel: snd_sof:sof_ipc4_widget_setup: sof-audio-pci-intel-mtl 0000:00:1f.3:
    Create widget host-copier.0.playback instance 0 - pipe 1 - core 0
    [  334.818442] kernel: snd_sof:sof_ipc4_log_header: sof-audio-pci-intel-mtl 0000:00:1f.3:
    ipc tx      : 0x40000004|0x15: MOD_INIT_INSTANCE [data size: 84]

    In practice, sof-test only capture kernel message and firmware trace generated during a test
    case run. Mostly in manual tests, if the kernel message file contains multiple firmware runs
    with overlapping information, the last one wins.
    '''
    with open(args.kmsg, encoding='utf8') as f:
        ppln_id = None
        for line in f:
            if match_obj := re.search(r'Create widget', line):
                span_end_pos = match_obj.span()[1]
                line_split = line[span_end_pos + 1:].split()
                widget_name = line_split[0]
                # In the linux kernel, IDA is used to allocated pipeline widget instance ID,
                # this ID later is used for pipeline creation, thus becomes pipeline ID in the
                # firmware. Note that ppln_id variable will be assigned properly at pipeline widget
                # creation, because it is always the first one to be created before all other
                # widgets in the same pipeline and pipelines are created sequentially.
                if widget_name.startswith('pipeline'):
                    ppln_id = line_split[2]
                next_line = next(f)
                widget_id = next_line.split('|')[0].split(':')[-1].strip()
                # convert to the same ID format in mtrace
                widget_id = int('0x' + widget_id[-6:], 16)
                component_name[Component(ppln_id, widget_id)] = widget_name

def analyze_perf_info():
    '''Calculate performance statistics from performance information'''
    for comp, perf_info_list in perf_info.items():
        len_perf_info = len(perf_info_list)
        cpu_avg_list = [e.cpu_avg for e in perf_info_list]
        cpu_peak_list = [e.cpu_peak for e in perf_info_list]
        avg_cpu_avg = sum(cpu_avg_list) / len_perf_info
        max_cpu_avg = max(cpu_avg_list)
        min_cpu_avg = min(cpu_avg_list)
        avg_cpu_peak = sum(cpu_peak_list) / len_perf_info
        max_cpu_peak = max(cpu_peak_list)
        min_cpu_peak = min(cpu_peak_list)
        perf_stats[comp] = CompPerfStats(avg_cpu_avg, max_cpu_avg, min_cpu_avg,
                                         avg_cpu_peak, max_cpu_peak, min_cpu_peak)

def output_to_csv(lines: list[str]):
    '''Output SOF performance statistics to csv file'''
    with open(args.out2csv, 'w', encoding='utf8') as f: # type: ignore[attr-defined]
        f.writelines(lines)

# pylint: disable=R0914
def format_perf_info() -> list[str] | None:
    '''Format SOF trace performance statistics'''
    if len(perf_stats):
        lines: list[str] = []
        max_name_len = max(len(name) for name in component_name.values())
        name_fmt = '{:>' + f'{max_name_len}' + '},'
        title_fmt = name_fmt + ' {:>10}, {:>12}, {:>12}, {:>12},'
        title_fmt = title_fmt + ' {:>13}, {:>13}, {:>13}, {:>18}'
        title = title_fmt.format('COMP_NAME', 'COMP_ID', 'CPU_AVG(MIN)', 'CPU_AVG(AVG)',
                                 'CPU_AVG(MAX)', 'CPU_PEAK(MIN)', 'CPU_PEAK(AVG)', 'CPU_PEAK(MAX)',
                                 'PEAK(MAX)/AVG(AVG)')
        lines.append(title + '\n')

        stats_fmt = name_fmt + ' {:>10}, {:>12,.2f}, {:>12,.2f}, {:>12,.2f},'
        stats_fmt = stats_fmt + ' {:>13,.2f}, {:>13,.2f}, {:>13,.2f}, {:>18,.2f}'
        for comp, perf in perf_stats.items():
            avg_cpu_avg_mcps = perf.avg_cpu_avg * TICK_TO_MCPS
            max_cpu_avg_mcps = perf.max_cpu_avg * TICK_TO_MCPS
            min_cpu_avg_mcps = perf.min_cpu_avg * TICK_TO_MCPS
            avg_cpu_peak_mcps = perf.avg_cpu_peak * TICK_TO_MCPS
            max_cpu_peak_mcps = perf.max_cpu_peak * TICK_TO_MCPS
            min_cpu_peak_mcps = perf.min_cpu_peak * TICK_TO_MCPS

            peak_to_avg_ratio = max_cpu_peak_mcps / avg_cpu_avg_mcps

            comp_name = component_name.get(comp, 'None')
            comp_id = f'{comp.ppln_id}-{comp.comp_id:#08x}'
            stat = stats_fmt.format(comp_name, comp_id, min_cpu_avg_mcps, avg_cpu_avg_mcps,
                                    max_cpu_avg_mcps, min_cpu_peak_mcps, avg_cpu_peak_mcps,
                                    max_cpu_peak_mcps, peak_to_avg_ratio)
            lines.append(stat + '\n')
        return lines
    return None

def print_perf_info():
    '''Format and output SOF performance info'''
    lines = format_perf_info()
    if lines is not None:
        for line in lines:
            print(line, end='')

        if args.out2csv is not None:
            output_to_csv(lines)

def parse_args():
    '''Parse command line arguments'''
    parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter,
                                     description=__doc__)
    parser.add_argument('filename')
    parser.add_argument('--kmsg', type=pathlib.Path, required=False,
                        help='Kernel message file captured with journalctl or other log utility')
    parser.add_argument('--out2csv', type=pathlib.Path, required=False,
                    help='Output SOF performance statistics to csv file')
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

    if args.kmsg is not None:
        process_kmsg_file()

    analyze_perf_info()

    print_perf_info()

if __name__ == "__main__":
    main()
