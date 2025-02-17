#!/usr/bin/env python3

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.
# pylint: disable=line-too-long, too-few-public-methods, missing-function-docstring
# pylint: disable=too-many-arguments, consider-using-f-string, too-many-instance-attributes
# pylint: disable=too-many-locals, too-many-return-statements, too-many-format-args, invalid-name
# pylint: disable=too-many-public-methods, consider-using-dict-items, consider-using-with

'''The sof-ipc-timer collects module initialization and configuration
timings from 'journalctl -k -o short-precise' output if SOF IPC debug
is enabled.

Without any flags there is no output. If you want it all, just put
everything on the command line: -t -i -c -b -p -s

Add firmware log from the same test sequence to get more accurate
processing times: -f <fw log file>

Note! Thw FW log file should be generated with FW built with
CONFIG_DEBUG_IPC_TIMINGS Kconfig option.

Use -C and -E flag to get min, max, and average of total sum of all
messages in one test cycle. Use -C for the first message that should
be part of the sum and -E for the last message. The messages can be
the same message (but then one cycle is lost).

For example: -C "0x11000007|0x200000" -E "0x12010000|0x0"

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
    fw_init_times: list
    fw_conf_times: list

    def __init__(self, pipe_id, comp_id, wname):
        self.pipe_id = pipe_id
        self.comp_id = comp_id
        self.wname = wname
        self.init_times = []
        self.conf_times = []
        self.fw_init_times = []
        self.fw_conf_times = []

    def __str__(self) -> str:
        return f'{self.pipe_id}-{self.comp_id:#08x}'

class Pipeline:
    '''SOF audio pipeline storage class'''
    pipe_id: int
    pipe_inst: int
    comps: list
    state_times: dict
    fw_state_times: dict
    create_times: list
    fw_create_times: list
    delete_times: list
    fw_delete_times: list

    def __init__(self, pipe_id):
        self.pipe_id = pipe_id
        self.pipe_inst = -1
        self.comps = []
        self.state_times = {}
        self.fw_state_times = {}
        self.create_times = []
        self.fw_create_times = []
        self.delete_times = []
        self.fw_delete_times = []

    def __str__(self) -> str:
        return f'pipeline.{self.pipe_id}'

    def add_state_timing(self, state, usecs):
        if self.state_times.get(state) is None:
            self.state_times[state] = []
        self.state_times[state].append(usecs)

    def add_fw_state_timing(self, state, usecs):
        if self.fw_state_times.get(state) is None:
            self.fw_state_times[state] = []
        self.fw_state_times[state].append(usecs)

class Binding:
    '''SOF audio storage class for multi pipeline trigger messages'''
    src_id: int
    sink_id: int
    bind_times: list
    fw_bind_times: list
    unbind_times: list
    fw_unbind_times: list

    def __init__(self, src_id, sink_id):
        self.src_id = src_id
        self.sink_id = sink_id
        self.bind_times =  []
        self.fw_bind_times =  []
        self.unbind_times =  []
        self.fw_unbind_times =  []

class MultiPipe:
    '''SOF audio storage class for multi pipeline trigger messages'''
    pipe_ids: list
    state_times: dict
    fw_state_times: dict

    def __init__(self, pipe_ids):
        self.pipe_ids = pipe_ids
        self.state_times = {}
        self.fw_state_times = {}

    def __str__(self) -> str:
        if self.pipe_ids is None or len(self.pipe_ids) == 0:
            return "pipes: anonymous"
        pipes = "pipes"
        for pipe_id in self.pipe_ids:
            pipes = pipes + f' {pipe_id}'
        pipes = pipes + ":"
        return pipes

    def add_state_timing(self, state, usecs):
        if self.state_times.get(state) is None:
            self.state_times[state] = []
        self.state_times[state].append(usecs)

    def add_fw_state_timing(self, state, usecs):
        if self.fw_state_times.get(state) is None:
            self.fw_state_times[state] = []
        self.fw_state_times[state].append(usecs)

class LogLineParser:
    '''Base class for different line parser classes. The main purpose
    is to store the common data-members from parent object
    SOFLinuxLogParser. '''
    def __init__(self):
        self.args = None
        self.comp_data = None
        self.pipe_data = None
        self.multip_data = None
        self.bind_data = None
        self.case_times = None
        self.fw_case_times = None

    def initialize(self, args, comp_data, pipe_data, multip_data, bind_data, case_times,
                   fw_case_times):
        self.args = args
        self.comp_data = comp_data
        self.pipe_data = pipe_data
        self.multip_data = multip_data
        self.bind_data = bind_data
        self.case_times = case_times
        self.fw_case_times = fw_case_times

    def copy(self, template):
        self.args = template.args
        self.comp_data = template.comp_data
        self.pipe_data = template.pipe_data
        self.multip_data = template.multip_data
        self.bind_data = template.bind_data
        self.case_times = template.case_times
        self.fw_case_times = template.fw_case_times

class PipelineParser(LogLineParser):
    '''Parse line of form

    Feb 25 23:17:00.598919 lnlm-rvp-sdw kernel: snd_sof:sof_ipc4_widget_setup: sof-audio-pci-intel-lnl 0000:00:1f.3: Create pipeline pipeline.1 (pipe 1) - instance 0, core 0

    'pipe_id' from ' instance 0,'
    '''
    def __init__(self, template):
        super().__init__()
        super().copy(template)

    def parse_line(self, line):
        if match_obj := re.search(r" Create pipeline ", line):
            match_end_pos = match_obj.span()[1]
            line_split = line[match_end_pos + 1:].split()
            pipe_id = int(line_split[2].rstrip(")"))
            pipe_inst = int(line_split[5].rstrip(","))
            if self.pipe_data.get(pipe_id) is None:
                self.pipe_data[pipe_id] = Pipeline(pipe_id)
            self.pipe_data[pipe_id].pipe_inst = pipe_inst
            return True
        return False

class WidgetParser(LogLineParser):
    '''Parse line of form:

    Feb 25 23:17:00.599838 lnlm-rvp-sdw kernel: snd_sof:sof_ipc4_widget_setup: sof-audio-pci-intel-lnl 0000:00:1f.3: Create widget host-copier.0.playback (pipe 1) - ID 4, instance 0, core 0

    'widget_name' from 'host-copier.0.playback'
    'pipi_id' integer form "(pipe 1)"
    'widget_id' MSB integer from "instance 0," and LSB from "ID 4,"
    '''
    def __init__(self, template):
        super().__init__()
        super().copy(template)

    def parse_line(self, line):
        if match_obj := re.search(r" Create widget ", line):
            match_end_pos = match_obj.span()[1]
            line_split = line[match_end_pos:].split()
            widget_name = line_split[0]
            # pipeline id
            pipe_id = int(line_split[2].rstrip(")"))
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

def state_str(state):
    if state == 0:
        return "INVALID_STATE"
    if state == 1:
        return "UNINITIALIZED"
    if state == 2:
        return "RESET"
    if state == 3:
        return "PAUSED"
    if state == 4:
        return "RUNNING"
    if state == 5:
        return "EOS"
    # This is extra state is to separete 1st pause messge after
    # pipeline creation from the other pause state changes that
    # actually do something.
    if state == 10:
        return "1.PAUSED"
    return f'<bad state {state}>'

class IpcMsgParser(LogLineParser):
    '''Class to parse all necessary information related to IPC
    messages. See documentation of parse_*_line() methods for details.

    '''
    comp_id: int
    sink_id: int
    pipe_id: int
    start: int
    state: int
    trigger_cmd: int
    case_time_sum: int
    case_time_fw_sum: int

    def __init__(self, template, fwlog_file):
        super().__init__()
        super().copy(template)
        self.reset()
        self.fwlog_file = fwlog_file
        self.fwlog_pos = 0
        self.fwlog_err_count = 0
        self.case_time_sum = -1
        self.case_time_fw_sum = -1
        self.multip_ids = None

    def state_s(self):
        return state_str(self.state)

    def parse_dai_trigger_cmd_line(self, line):
        ''' Parse line of form:

        Mar 20 18:22:49.887735 lnlm-rvp-sdw kernel: snd_sof_intel_hda_common:hda_dai_trigger: sof-audio-pci-intel-lnl 0000:00:1f.3: cmd=1 dai SSP2 Pin direction 0

        To extract cmd code, 0 for stopping, 1 for starting. '''
        if line.find(":hda_dai_trigger:") >= 0:
            find_str = ": cmd="
            index = line.find(find_str)
            if index >= 0:
                self.trigger_cmd = int(line[index + len(find_str):].split()[0])
            return True
        return False

    def parse_multi_pipe_trigger_cmd_line(self, line):
        ''' Parse line of form:

        Mar 20 18:22:49.890322 lnlm-rvp-sdw kernel: snd_sof:sof_ipc4_trigger_pipelines: sof-audio-pci-intel-lnl 0000:00:1f.3: pcm2 (Port2), dir 0: cmd: 1, state: 4

        To extract cmd code, 0 for stopping, 1 for starting. '''
        if line.find(":sof_ipc4_trigger_pipelines:") >= 0:
            find_str = ": cmd: "
            index = line.find(find_str)
            if index >= 0:
                self.trigger_cmd = int(line[index + len(find_str):].split()[0].rstrip(","))
            return True
        return False

    def parse_multi_pipe_trigger_params_line(self, line):
        ''' Parse line of form:

        Mar 20 18:22:51.866538 lnlm-rvp-sdw kernel: snd_sof:sof_ipc4_set_multi_pipeline_state: sof-audio-pci-intel-lnl 0000:00:1f.3: Pipelines 1 0 state switching to RESET (2)

        To extract pipeline instances included into multi pipeline
        GLB_SET_PIPELINE_STATE message. '''
        if line.find(":sof_ipc4_set_multi_pipeline_state:") >= 0:
            start_str = "Set pipelines "
            index = line.find(start_str)
            end_pos = line.find(" to state ")
            if index >= 0 and end_pos >= 0:
                pipe_ids = []
                start_pos = index + len(start_str)
                for inst_str in line[start_pos:end_pos].split():
                    for pipe_id in self.pipe_data:
                        if self.pipe_data[pipe_id].pipe_inst == int(inst_str):
                            pipe_ids.append(pipe_id)
                self.multip_ids = pipe_ids
                return True
        return False


    def parse_ipc_headers_line(self, line):
        '''Parse three consequtive lines of form:

        Feb 25 23:17:00.599946 lnlm-rvp-sdw kernel: snd_sof:sof_ipc4_log_header: sof-audio-pci-intel-lnl 0000:00:1f.3: ipc tx      : 0x40000004|0x15: MOD_INIT_INSTANCE [data size: 84]
        Feb 25 23:17:00.600048 lnlm-rvp-sdw kernel: snd_sof:sof_ipc4_log_header: sof-audio-pci-intel-lnl 0000:00:1f.3: ipc tx reply: 0x60000000|0x15: MOD_INIT_INSTANCE
        Feb 25 23:17:00.600185 lnlm-rvp-sdw kernel: snd_sof:sof_ipc4_log_header: sof-audio-pci-intel-lnl 0000:00:1f.3: ipc tx done : 0x40000004|0x15: MOD_INIT_INSTANCE [data size: 84]

        'usecs' from '23:17:00.599946' (please do not run your tests over midnight)
        'msg_type' from 5 letters following " ipc tx ", either "     ", "reply", or "done "
        'msg_str' from '0x40000004|0x15'
        'msg_name' from 'MOD_INIT_INSTANCE' ('MOD_LARGE_CONFIG_SET' or 'GLB_SET_PIPELINE_STATE')
        'primary' integer from '0x40000004'
        'extension' integer from '0x15'
        '''
        if match_obj := re.search(r" ipc tx (     |reply|done )", line):
            match_start_pos = match_obj.span()[0]
            match_end_pos = match_obj.span()[1]
            line_split = line.split()
            dt_object = datetime.strptime(line_split[2], "%H:%M:%S.%f")
            secs = dt_object.second + dt_object.minute * 60 + dt_object.hour * 3600
            usecs = secs * 1000000 + dt_object.microsecond
            msg_type = line[match_start_pos + 8 : match_end_pos]
            msg_part = line[match_end_pos:].split()
            msg_str = msg_part[1].rstrip(":")
            msg_name = msg_part[2]
            primary = int(msg_str.split('|')[0], 16)
            extension = int(msg_str.split('|')[1], 16)
            if msg_type == "     ":
                self.start = usecs
            if msg_name == "GLB_CREATE_PIPELINE":
                self.glb_create_pipe_msg_parse(msg_type, msg_str, usecs, primary)
            elif msg_name == "GLB_DELETE_PIPELINE":
                self.glb_delete_pipe_msg_parse(msg_type, msg_str, usecs, primary)
            elif msg_name == "MOD_INIT_INSTANCE":
                self.mod_init_msg_parse(msg_type, msg_str, usecs, primary)
            elif msg_name == "MOD_LARGE_CONFIG_SET":
                self.mod_conf_msg_parse(msg_type, msg_str, usecs, primary)
            elif msg_name == "MOD_BIND":
                self.mod_bind_msg_parse(msg_type, msg_str, usecs, primary, extension)
            elif msg_name == "MOD_UNBIND":
                self.mod_unbind_msg_parse(msg_type, msg_str, usecs, primary, extension)
            elif msg_name == "GLB_SET_PIPELINE_STATE":
                self.glb_set_pipe_msg_parse(msg_type, msg_str, usecs, primary, extension)
            return True
        return False

    def parse_line(self, line):
        if self.parse_dai_trigger_cmd_line(line):
            return True
        if self.parse_multi_pipe_trigger_cmd_line(line):
            return True
        if self.parse_multi_pipe_trigger_params_line(line):
            return True
        if self.parse_ipc_headers_line(line):
            return True
        return False

    def case_sum(self, msg_str, k_usec, fw_usec):
        if msg_str == self.args.case_end:
            if self.case_time_sum >= 0:
                self.case_time_sum = self.case_time_sum + k_usec
                self.case_times.append(self.case_time_sum)
                if self.case_time_fw_sum >= 0:
                    if not fw_usec is None:
                        self.case_time_fw_sum = self.case_time_fw_sum + fw_usec
                    self.fw_case_times.append(self.case_time_fw_sum)
        if msg_str == self.args.case_start:
            self.case_time_sum = k_usec
            if not fw_usec is None:
                self.case_time_fw_sum = fw_usec
        elif self.case_time_sum >= 0:
            self.case_time_sum = self.case_time_sum + k_usec
            if not fw_usec is None:
                self.case_time_fw_sum = self.case_time_fw_sum + fw_usec

    def fw_lookup(self, msg_str):
        ''' To make this function work robustly also with the mtrace files,
        that quite often have holes in them, some kind of time stamp
        comparison should be done to see that the corresponding FW message
        in the FW logs was found in approximately at correct timing time
        stamp. '''
        if not self.fwlog_file is None:
            prev_pos = self.fwlog_pos
            for line in self.fwlog_file:
                self.fwlog_pos = self.fwlog_pos + len(line)
                line = line.decode('utf8').strip()
                index = line.find(msg_str)
                if index > 0:
                    if self.fwlog_pos - prev_pos > 10000:
                        print("Warning: position jumping a lot %d" % (self.fwlog_pos - prev_pos))
                    usecs = int(line[index:].split()[2])
                    return usecs
            self.fwlog_file.seek(prev_pos)
            self.fwlog_pos = prev_pos
            if self.fwlog_err_count == 0:
                print("Warning matching line for %s message not found" % msg_str)
            self.fwlog_err_count = self.fwlog_err_count + 1
        return None

    def reset(self):
        self.comp_id = -1
        self.sink_id = -1
        self.pipe_id = -1
        self.start = -1
        self.state = -1
        self.trigger_cmd = -1
        self.multip_ids = None
        self.bind_ids = None

    def fw_time(self, fw_usec):
        if not fw_usec is None:
            return "\tfw " + str(fw_usec) + " us"
        return ""

    def mod_msg_parse_1st(self, primary):
        self.comp_id = primary & 0xFFFFFF
        if self.comp_id == 0:
            self.comp_id = None

    def mod_init_msg_parse(self, msg_type, msg_str, usecs, primary):
        if msg_type == "     ":
            self.mod_msg_parse_1st(primary)
        if self.comp_id is None or self.comp_data.get(self.comp_id) is None:
            return
        comp = self.comp_data[self.comp_id]
        if msg_type == "reply" and self.args.reply_timings and self.args.init_messages:
            print("%s:\tinit reply\t%d us" % (comp.wname, usecs - self.start))
        elif msg_type == "done ":
            fw_usec = self.fw_lookup(msg_str)
            self.case_sum(msg_str, usecs - self.start, fw_usec)
            if self.args.init_messages:
                print("%s:\tinit done\t%d us%s\t%s" %
                      (comp.wname, usecs - self.start, self.fw_time(fw_usec), msg_str))
            comp.init_times.append(usecs - self.start)
            if not fw_usec is None:
                comp.fw_init_times.append(fw_usec)
            self.reset()

    def mod_conf_msg_parse(self, msg_type, msg_str, usecs, primary):
        if msg_type == "     ":
            self.mod_msg_parse_1st(primary)
        if self.comp_id is None or self.comp_data.get(self.comp_id) is None:
            return
        comp = self.comp_data[self.comp_id]
        if msg_type == "reply" and self.args.reply_timings and self.args.config_messages:
            print("%s:\tconf reply\t%d us" % (comp.wname, usecs - self.start))
        elif msg_type == "done ":
            fw_usec = self.fw_lookup(msg_str)
            self.case_sum(msg_str, usecs - self.start, fw_usec)
            if self.args.config_messages:
                print("%s:\tconf done\t%d us%s\t%s" %
                      (comp.wname, usecs - self.start, self.fw_time(fw_usec), msg_str))
            comp.conf_times.append(usecs - self.start)
            if not fw_usec is None:
                comp.fw_conf_times.append(fw_usec)
            self.reset()

    def mod_bind_data(self):
        key = (self.sink_id << 24) | self.comp_id
        if self.bind_data.get(key) is None:
            self.bind_data[key] = Binding(self.comp_id, self.sink_id)
        return self.bind_data[key]

    def mod_bind_msg_parse(self, msg_type, msg_str, usecs, primary, extension):
        if msg_type == "     ":
            self.mod_msg_parse_1st(primary)
            self.sink_id = extension & 0xFFFFFF
        if self.comp_data.get(self.comp_id) is None or self.comp_data.get(self.sink_id) is None:
            return
        comp = self.comp_data[self.comp_id]
        sink = self.comp_data[self.sink_id]
        if msg_type == "reply" and self.args.reply_timings and self.args.binding_messages:
            print("%s->%s:\tbind reply\t%d us" % (comp.wname, sink.wname, usecs - self.start))
        elif msg_type == "done ":
            fw_usec = self.fw_lookup(msg_str)
            self.case_sum(msg_str, usecs - self.start, fw_usec)
            if self.args.binding_messages:
                print("%s->%s:\tbind done\t%d us%s\t%s" %
                      (comp.wname, sink.wname, usecs - self.start, self.fw_time(fw_usec), msg_str))
            binding = self.mod_bind_data()
            binding.bind_times.append(usecs - self.start)
            if not fw_usec is None:
                binding.fw_bind_times.append(fw_usec)
            self.reset()

    def mod_unbind_msg_parse(self, msg_type, msg_str, usecs, primary, extension):
        if msg_type == "     ":
            self.mod_msg_parse_1st(primary)
            self.sink_id = extension & 0xFFFFFF
        if self.comp_data.get(self.comp_id) is None or self.comp_data.get(self.sink_id) is None:
            return
        comp = self.comp_data[self.comp_id]
        sink = self.comp_data[self.sink_id]
        if msg_type == "reply" and self.args.reply_timings and self.args.binding_messages:
            print("%s->%s:\tunbind reply\t%d us" % (comp.wname, sink.wname, usecs - self.start))
        elif msg_type == "done ":
            fw_usec = self.fw_lookup(msg_str)
            self.case_sum(msg_str, usecs - self.start, fw_usec)
            if self.args.binding_messages:
                print("%s->%s:\tunbind done\t%d us%s\t%s" %
                      (comp.wname, sink.wname, usecs - self.start, self.fw_time(fw_usec), msg_str))
            binding = self.mod_bind_data()
            binding.unbind_times.append(usecs - self.start)
            if not fw_usec is None:
                binding.fw_unbind_times.append(fw_usec)
            self.reset()

    def multip_key(self):
        if self.multip_ids is None:
            return "anonymous"
        pipes_key = ""
        for i in self.multip_ids:
            pipes_key = pipes_key + " " + str(i)
        return pipes_key

    def glb_msg_1st_init_pipe_id(self, primary):
        pipe_inst = (primary & 0x00FF0000) >> 16
        for pipe_id in self.pipe_data:
            if self.pipe_data[pipe_id].pipe_inst == pipe_inst:
                self.pipe_id = pipe_id

    def glb_set_pipe_parse_done(self, msg_str, usecs):
        fw_usec = self.fw_lookup(msg_str)
        self.case_sum(msg_str, usecs - self.start, fw_usec)
        pipeid = ""
        if self.pipe_id < 0:
            pipeid = "pipes:" + self.multip_key()
        else:
            pipeid = "pipeline." + str(self.pipe_id)
        if self.args.trigger_nessages:
            print("%s\tto %s done\t%d us%s\t%s" %
                  (pipeid, self.state_s(), usecs - self.start, self.fw_time(fw_usec), msg_str))
        # If this is part of cmd 1 trigger, classify it separately
        if self.trigger_cmd == 1 and self.state == 3:
            self.state = 10
        if self.pipe_id < 0:
            if self.multip_data.get(self.multip_key()) is None:
                self.multip_data[self.multip_key()] = MultiPipe(self.multip_ids)
            self.multip_data[self.multip_key()].add_state_timing(self.state, usecs - self.start)
            if not fw_usec is None:
                self.multip_data[self.multip_key()].add_fw_state_timing(self.state, fw_usec)
        else:
            self.pipe_data[self.pipe_id].add_state_timing(self.state, usecs - self.start)
            if not fw_usec is None:
                self.pipe_data[self.pipe_id].add_fw_state_timing(self.state, fw_usec)
            self.reset()

    def glb_set_pipe_msg_parse(self, msg_type, msg_str, usecs, primary, extension):
        if msg_type == "     ":
            self.state = primary & 0xFFFF
            if extension == 0:
                self.glb_msg_1st_init_pipe_id(primary)
        elif msg_type == "reply":
            if self.args.trigger_nessages and self.args.reply_timings:
                print("pipeline.%d\tto %s reply\t %d us" %
                      (self.pipe_id, self.state_s(), usecs - self.start))
        elif msg_type == "done ":
            self.glb_set_pipe_parse_done(msg_str, usecs)

    def glb_create_pipe_msg_parse(self, msg_type, msg_str, usecs, primary):
        if msg_type == "     ":
            self.glb_msg_1st_init_pipe_id(primary)
        elif msg_type == "reply" and self.args.reply_timings and self.args.pipeline_msgs:
            print("pipeline.%d\tcreate reply\t %d us" %
                  (self.pipe_id, self.state, usecs - self.start))
        elif msg_type == "done ":
            fw_usec = self.fw_lookup(msg_str)
            self.case_sum(msg_str, usecs - self.start, fw_usec)
            if self.args.pipeline_msgs:
                print("pipeline.%d\tcreate done\t%d us%s\t%s" %
                      (self.pipe_id, usecs - self.start, self.fw_time(fw_usec), msg_str))
            if self.pipe_id < 0:
                return
            self.pipe_data[self.pipe_id].create_times.append(usecs - self.start)
            if not fw_usec is None:
                self.pipe_data[self.pipe_id].fw_create_times.append(fw_usec)
            self.reset()

    def glb_delete_pipe_msg_parse(self, msg_type, msg_str, usecs, primary):
        if msg_type == "     ":
            self.glb_msg_1st_init_pipe_id(primary)
        elif msg_type == "reply" and self.args.reply_timings and self.args.pipeline_msgs:
            print("pipeline.%d\tdelete reply\t %d us" %
                  (self.pipe_id, self.state, usecs - self.start))
        elif msg_type == "done ":
            fw_usec = self.fw_lookup(msg_str)
            self.case_sum(msg_str, usecs - self.start, fw_usec)
            if self.args.pipeline_msgs:
                print("pipeline.%d\tdelete done\t%d us%s\t%s" %
                      (self.pipe_id, usecs - self.start, self.fw_time(fw_usec), msg_str))
            if self.pipe_id < 0:
                return
            self.pipe_data[self.pipe_id].delete_times.append(usecs - self.start)
            if not fw_usec is None:
                self.pipe_data[self.pipe_id].fw_delete_times.append(fw_usec)
            self.reset()

class SOFLinuxLogParser:
    '''Class parser object that goes through then Linux kernel log
    line by line and picks some of the data from the matching FW logs,
    if the FW log file was give. '''
    def __init__(self, args, fwlog_file):
        self.args = args
        self.comp_data = {}
        self.pipe_data = {}
        self.multip_data = {}
        self.bind_data = {}
        self.case_times = []
        self.fw_case_times = []
        self.common_data = LogLineParser()
        self.common_data.initialize(args, self.comp_data, self.pipe_data, self.multip_data,
                                    self.bind_data, self.case_times, self.fw_case_times)
        self.pipe_parser = PipelineParser(self.common_data)
        self.widget_parser = WidgetParser(self.common_data)
        self.ipc_msg_parser = IpcMsgParser(self.common_data, fwlog_file)

    def read_log_data(self, klog_file):
        for line in klog_file:
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

    def bind_str(self, binding):
        src = self.comp_data[binding.src_id]
        sink = self.comp_data[binding.sink_id]
        return src.wname + ">" + sink.wname

    def summary_comp(self):
        for comp_id in self.comp_data:
            mod = self.comp_data[comp_id]
            if not self.args.fw_only:
                self.print_min_max_avg(mod.wname + "    init", mod.init_times)
            self.print_min_max_avg(mod.wname + " fw init", mod.fw_init_times)
            if not self.args.fw_only:
                self.print_min_max_avg(mod.wname + "    conf", mod.conf_times)
            self.print_min_max_avg(mod.wname + " fw conf", mod.fw_conf_times)

    def summary_pipe(self):
        for pipe_id in self.pipe_data:
            pipe = self.pipe_data[pipe_id]
            print("%s:" % pipe, end=" ")
            for comp in pipe.comps:
                print("%s" % comp.wname, end=", ")
            print()
            if not self.args.fw_only:
                self.print_min_max_avg(str(pipe) + " create ", pipe.create_times)
                for state in pipe.state_times:
                    state_times_list = pipe.state_times[state]
                    self.print_min_max_avg(str(pipe) + " " + state_str(state) + "   ",
                                           state_times_list)
                self.print_min_max_avg(str(pipe) + " delete ", pipe.delete_times)
            self.print_min_max_avg(str(pipe) + " create fw ", pipe.fw_create_times)
            for state in pipe.fw_state_times:
                state_times_list = pipe.fw_state_times[state]
                self.print_min_max_avg(str(pipe) + " " + state_str(state) + " fw",
                                       state_times_list)
            self.print_min_max_avg(str(pipe) + " delete fw ", pipe.fw_delete_times)

    def summary_bind(self):
        for bind_key in self.bind_data:
            binding = self.bind_data[bind_key]
            if not self.args.fw_only:
                self.print_min_max_avg(self.bind_str(binding) + "\tbind ", binding.bind_times)
            self.print_min_max_avg(self.bind_str(binding) + "\tbind fw ", binding.fw_bind_times)
            if not self.args.fw_only:
                self.print_min_max_avg(self.bind_str(binding) + "\tunbind ", binding.unbind_times)
            self.print_min_max_avg(self.bind_str(binding) + "\tunbind fw ", binding.fw_unbind_times)

    def summary_multi_pipe(self):
        for multip_key in self.multip_data:
            multip = self.multip_data[multip_key]
            if not self.args.fw_only:
                for state in multip.state_times:
                    state_times_list = multip.state_times[state]
                    self.print_min_max_avg(str(multip) + " " + state_str(state) + "   ",
                                           state_times_list)
            for state in multip.fw_state_times:
                state_times_list = multip.fw_state_times[state]
                self.print_min_max_avg(str(multip) + " " + state_str(state) + " fw",
                                       state_times_list)

    def summary(self):
        if not self.args.summary:
            return
        self.summary_comp()
        self.summary_pipe()
        self.summary_bind()
        self.summary_multi_pipe()

    def case_totals(self):
        if self.args.case_start is None or self.args.case_end is None:
            return
        if not self.args.fw_only:
            self.print_min_max_avg("IPC totals    ", self.case_times)
        self.print_min_max_avg("IPC totals fw ", self.fw_case_times)

    def get_fwlog_err_count(self):
        return self.ipc_msg_parser.fwlog_err_count

def parse_args():

    '''Parse command line arguments'''
    parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter,
                                     description=__doc__)
    parser.add_argument('filename', nargs="?", help="Optional log file, stdin if not defined")
    parser.add_argument("-f", "--fw-log-file",
                        help="FW log file to scan for corresponding IPC timing data",
                        default=None,)
    parser.add_argument("-C", "--case-start",
                        help="Test case start mark message to calculate total sum of all message " +
                        "handling times between this and end messages.",
                        default=None,)
    parser.add_argument("-E", "--case-end",
                        help="Test case end mark message to calculate total sum of all message " +
                        "handling times from start to this messages.",
                        default=None,)
    parser.add_argument('-t', '--trigger-nessages', action="store_true", default=False,
                        help='Show trigger message handling times')
    parser.add_argument('-p', '--pipeline-msgs', action="store_true", default=False,
                        help='Show pipeline create and delete messages')
    parser.add_argument('-i', '--init-messages', action="store_true", default=False,
                        help='Show init message handling times')
    parser.add_argument('-c', '--config-messages', action="store_true", default=False,
                        help='Show large config set message handling times')
    parser.add_argument('-b', '--binding-messages', action="store_true", default=False,
                        help='Show mod bind and unbind message handling times')
    parser.add_argument('-r', '--reply-timings', action="store_true", default=False,
                        help='Show time to reply message')
    parser.add_argument('-s', '--summary', action="store_true", default=False,
                        help='Show average, max, and min latencies of message handling')
    parser.add_argument('-F', '--fw-only', action="store_true", default=False,
                        help='Show only FW numbers in summary')
    return parser.parse_args()

def main():
    args = parse_args()
    fw_log = None

    if args.fw_log_file is not None:
        fw_log = open(args.fw_log_file, 'rb')

    log_parser = SOFLinuxLogParser(args, fw_log)

    if args.filename is None:
        log_parser.read_log_data(sys.stdin)
    else:
        with open(args.filename, 'r', encoding='utf8') as file:
            log_parser.read_log_data(file)

    if fw_log is not None:
        fw_log.close()

    log_parser.summary()

    log_parser.case_totals()

    fwlog_err_count = log_parser.get_fwlog_err_count()
    if fwlog_err_count > 0:
        print("Warning could not find matching FW logs for %d messages" %
              fwlog_err_count)

if __name__ == "__main__":
    main()
