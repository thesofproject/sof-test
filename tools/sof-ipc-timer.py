#!/usr/bin/env python3

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.

'''The sof-ipc-timer collects module initialization and configuration
timings from 'journalctl -k -o short-precise' output if SOF IPC debug
is enabled.

Without any flags there is no output. If you want it all, just put
everything on the command line: -t -i -c -m -p -s

'''

import re
import sys
import argparse
from datetime import datetime

class Component:
    '''SOF audio component storage class'''
    pipe_id: int
    comp_id: int
    wname: str
    init_times: list
    conf_times: list

    def __init__(self, pipe_id, comp_id, wname):
        self.pipe_id = pipe_id
        self.comp_id = comp_id
        self.wname = wname
        self.init_times = []
        self.conf_times = []

    def __str__(self) -> str:
        return f'{self.pipe_id}-{self.comp_id:#08x}'

class Pipeline:
    '''SOF audio pipeline storage class'''
    pipe_id: int
    comps: list
    state_times: dict

    def __init__(self, pipe_id):
        self.pipe_id = pipe_id
        self.comps = []
        self.state_times = {}

    def __str__(self) -> str:
        return f'pipeline.{self.pipe_id + 1}'

    def add_state_timing(self, state, usecs):
        if self.state_times.get(state) is None:
            self.state_times[state] = []
        self.state_times[state].append(usecs)

class LogLineParser:
    def __init__(self, args, comp_data, pipe_data):
        self.args = args
        self.comp_data = comp_data
        self.pipe_data = pipe_data

class PipelineParser(LogLineParser):
    '''Parse line of form

    Feb 25 23:17:00.598919 lnlm-rvp-sdw kernel: snd_sof:sof_ipc4_widget_setup: sof-audio-pci-intel-lnl 0000:00:1f.3: Create pipeline pipeline.1 (pipe 1) - instance 0, core 0

    'pipe_id' from ' instance 0,'
    '''
    def __init__(self, args, comp_data, pipe_data):
        super().__init__(args, comp_data, pipe_data)

    def parse_line(self, line):
        if match_obj := re.search(r" Create pipeline ", line):
            match_end_pos = match_obj.span()[1]
            line_split = line[match_end_pos + 1:].split()
            pipe_id = int(line_split[5].rstrip(","))
            if self.pipe_data.get(pipe_id) is None:
                self.pipe_data[pipe_id] = Pipeline(pipe_id)
            return True
        return False

class WidgetParser(LogLineParser):
    '''Parse line of form:

    Feb 25 23:17:00.599838 lnlm-rvp-sdw kernel: snd_sof:sof_ipc4_widget_setup: sof-audio-pci-intel-lnl 0000:00:1f.3: Create widget host-copier.0.playback (pipe 1) - ID 4, instance 0, core 0

    'widget_name' from 'host-copier.0.playback'
    'pipi_id' integer form "(pipe 1)"
    'widget_id' MSB integer from "instance 0," and LSB from "ID 4,"
    '''
    def __init__(self, args, comp_data, pipe_data):
        super().__init__(args, comp_data, pipe_data)

    def parse_line(self, line):
        if match_obj := re.search(r" Create widget ", line):
            match_end_pos = match_obj.span()[1]
            line_split = line[match_end_pos:].split()
            widget_name = line_split[0]
            # pipeline instance id is one smaller than the pipeline number
            pipe_id = int(line_split[2].rstrip(")")) - 1
            module_instance_id = int(line_split[7].rstrip(","))
            widget_id = int(line_split[5].rstrip(","))
            # final module id are composed with high16(module instance id) + low16(module id)
            widget_id |= module_instance_id << 16
            # do not overwire data we have colledted, only add new items to dictionary
            if self.comp_data.get(widget_id) is None:
                self.comp_data[widget_id] = Component(pipe_id, widget_id, widget_name)
                if not self.pipe_data.get(pipe_id) is None:
                    self.pipe_data[pipe_id].comps.append(self.comp_data[widget_id])
            return True
        return False

class IpcMsgParser(LogLineParser):
    '''Parse three consequtive lines of form:

    Feb 25 23:17:00.599946 lnlm-rvp-sdw kernel: snd_sof:sof_ipc4_log_header: sof-audio-pci-intel-lnl 0000:00:1f.3: ipc tx      : 0x40000004|0x15: MOD_INIT_INSTANCE [data size: 84]
    Feb 25 23:17:00.600048 lnlm-rvp-sdw kernel: snd_sof:sof_ipc4_log_header: sof-audio-pci-intel-lnl 0000:00:1f.3: ipc tx reply: 0x60000000|0x15: MOD_INIT_INSTANCE
    Feb 25 23:17:00.600185 lnlm-rvp-sdw kernel: snd_sof:sof_ipc4_log_header: sof-audio-pci-intel-lnl 0000:00:1f.3: ipc tx done : 0x40000004|0x15: MOD_INIT_INSTANCE [data size: 84]

    'usecs' from '23:17:00.599946' (please do not run your tests over midnight)-
    'msg_type' from 5 letters following " ipc tx ", either "     ", "reply", or "done "
    'msg_str' from '0x40000004|0x15'
    'msg_name' from 'MOD_INIT_INSTANCE' ('MOD_LARGE_CONFIG_SET' or 'GLB_SET_PIPELINE_STATE')
    'primary' integer from '0x40000004'
    'extension' integer from '0x15'
    '''
    comp_id: int
    pipe_id: int
    start: int
    state: int

    def __init__(self, args, comp_data, pipe_data):
        super().__init__(args, comp_data, pipe_data)
        self.reset()

    def reset(self):
        self.comp_id = -1
        self.pipe_id = -1
        self.start = -1
        self.state = -1

    def parse_line(self, line):
        if match_obj := re.search(r" ipc tx (     |reply|done )", line):
            match_start_pos = match_obj.span()[0]
            match_end_pos = match_obj.span()[1]
            line_split = line.split()
            dt_object = datetime.strptime(line_split[2], "%H:%M:%S.%f")
            secs = dt_object.second + dt_object.minute * 60 + dt_object.hour * 3600
            usecs = secs * 1000000 + dt_object.microsecond
            msg_type = line[match_start_pos + 8 : match_end_pos]
            msg_part = line[match_end_pos:].split()
            msg_str = msg_part[1]
            msg_name = msg_part[2]
            primary = int(msg_str.split('|')[0], 16)
            extension =  int(msg_str.split('|')[1].rstrip(":"), 16)
            if msg_name == "MOD_INIT_INSTANCE" or msg_part[2] == "MOD_LARGE_CONFIG_SET":
                self.parse_mod_msg(msg_name, msg_str, msg_type, usecs, primary)
            elif msg_name == "GLB_SET_PIPELINE_STATE":
                self.parse_glb_set_msg(msg_type, msg_str, usecs, primary)
            return True
        return False

    def parse_mod_1st(self, usecs, primary):
        self.comp_id = primary & 0xFFFFFF
        if self.comp_id == 0:
            self.comp_id = None
        self.start = usecs

    def parse_mod_reply(self, comp, msg_name, usecs):
        if msg_name == "MOD_INIT_INSTANCE" and self.args.init_messages:
            print("%s:\tinit reply\t%d us" % (comp.wname, usecs - self.start))
        elif msg_name == "MOD_LARGE_CONFIG_SET" and self.args.config_messages:
            print("%s:\tconf reply\t%d us" % (comp.wname, usecs - self.start))

    def parse_mod_done(self, comp, msg_name, msg_str, usecs):
        message = ""
        pipeline_id = ""
        if self.args.message:
            message = "\t" + msg_str
        if self.args.pipeline_id:
            pipeline_id = "\tpipeline id: " + str(comp.pipe_id)
        if msg_name == "MOD_INIT_INSTANCE":
            if self.args.init_messages:
                print("%s:\tinit done\t%d us%s%s" %
                      (comp.wname, usecs - self.start, message, pipeline_id))
            comp.init_times.append(usecs - self.start)
        elif msg_name == "MOD_LARGE_CONFIG_SET":
            if self.args.config_messages:
                print("%s:\tconf done\t%d us%s%s" %
                      (comp.wname, usecs - self.start, message, pipeline_id))
            comp.conf_times.append(usecs - self.start)
        self.reset()

    def parse_mod_msg(self, msg_name, msg_str, msg_type, usecs, primary):
        if msg_type == "     ":
            self.parse_mod_1st(usecs, primary)
        if self.comp_id == None:
            return
        comp = self.comp_data[self.comp_id]
        if msg_type == "reply" and self.args.reply_timings:
            self.parse_mod_reply(comp, msg_name, usecs)
        elif msg_type == "done ":
            self.parse_mod_done(comp, msg_name, msg_str, usecs)

    def parse_glb_set_1st(self, usecs, primary):
        self.pipe_id = (primary & 0x00FF0000) >> 16
        self.state = primary & 0xFFFF
        self.start = usecs

    def parse_glb_set_reply(self, usecs):
        print("pipeline id: %d\tstate %d reply\t %d us" %
              (self.pipe_id, self.state, usecs - self.start))
        self.start = usecs

    def parse_glb_set_done(self, msg_str, usecs):
        message = ""
        if self.args.message:
            message = "\t" + msg_str
        if self.args.trigger_nessages:
            print("pipeline id: %d\tstate %d done\t%d us%s" %
                  (self.pipe_id, self.state, usecs - self.start, message))
        self.pipe_data[self.pipe_id].add_state_timing(self.state, usecs - self.start)
        self.reset()

    def parse_glb_set_msg(self, msg_type, msg_str, usecs, primary):
        if msg_type == "     ":
            self.parse_glb_set_1st(usecs, primary)
        elif msg_type == "reply" and self.args.reply_timings:
            self.parse_glb_set_reply(usecs)
        elif msg_type == "done ":
            self.parse_glb_set_done(msg_str, usecs)

class SOFLinuxLogParser:
    def __init__(self, args):
        self.args = args
        self.comp_data = {}
        self.pipe_data = {}
        self.pipe_parser = PipelineParser(args, self.comp_data, self.pipe_data)
        self.widget_parser = WidgetParser(args, self.comp_data, self.pipe_data)
        self.ipc_msg_parser = IpcMsgParser(args, self.comp_data, self.pipe_data)

    def read_log_data(self, file):
        for line in file:
            if self.pipe_parser.parse_line(line):
                continue
            if self.widget_parser.parse_line(line):
                continue
            if self.ipc_msg_parser.parse_line(line):
                continue

    def print_min_max_avg(self, prefix, times):
        if len(times) == 0:
            return
        minval = 1000000
        maxval = 0
        valsum = 0
        for val in times:
            if val < minval:
                minval = val
            if val > maxval:
                maxval = val
            valsum = valsum + val
        print("%s\tmin %d us\tmax %d us\taverage %d us of %d" %
              (prefix, minval, maxval, valsum / len(times), len(times)))

    def summary(self):
        if not self.args.summary:
            return
        for comp_id in self.comp_data:
            mod = self.comp_data[comp_id]
            self.print_min_max_avg(mod.wname + " init", mod.init_times)
            self.print_min_max_avg(mod.wname + " conf", mod.conf_times)
        for pipe_id in self.pipe_data:
            pipe = self.pipe_data[pipe_id]
            print("%s:" % pipe, end=" ")
            for comp in pipe.comps:
                print("%s" % comp.wname, end=", ")
            print()
            for state in pipe.state_times:
                state_times_list = pipe.state_times[state]
                self.print_min_max_avg(str(pipe) + " " + str(state), state_times_list)

def parse_args():
    '''Parse command line arguments'''
    parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter,
                                     description=__doc__)
    parser.add_argument('filename', nargs="?", help="Optional log file, stdin if not defined")
    parser.add_argument('-t', '--trigger-nessages', action="store_true", default=False,
                        help='Show trigger message handling times')
    parser.add_argument('-i', '--init-messages', action="store_true", default=False,
                        help='Show init message handling times')
    parser.add_argument('-c', '--config-messages', action="store_true", default=False,
                        help='Show large config set message handling times')
    parser.add_argument('-r', '--reply-timings', action="store_true", default=False,
                        help='Show time to reply message, "done" time is from "reply"')
    parser.add_argument('-m', '--message', action="store_true", default=False,
                        help='Show 1st message primary and extension parts')
    parser.add_argument('-p', '--pipeline-id', action="store_true", default=False,
                        help='Show pipeline id')
    parser.add_argument('-s', '--summary', action="store_true", default=False,
                        help='Show average, max, and min latencies of message handling')
    return parser.parse_args()

def main():
    args = parse_args()
    log_parser = SOFLinuxLogParser(args)

    if args.filename is None:
        log_parser.read_log_data(sys.stdin)
    else:
        with open(args.filename, 'r', encoding='utf8') as file:
            log_parser.read_log_data(file)

    log_parser.summary()

if __name__ == "__main__":
    main()
