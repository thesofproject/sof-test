#!/usr/bin/env python3

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.

'''The sof-ipc-timer collects module initialization and configuration
timings from 'journalctl -k -o short-precise' output if SOF IPC debug
is enabled.

'''

import re
import pathlib
import argparse
from datetime import datetime

class Component:
    '''SOF audio component storage class'''
    ppln_id: str
    comp_id: int
    wname: str

    def __init__(self, ppln_id, comp_id, wname):
        self.ppln_id = ppln_id
        self.comp_id = comp_id
        self.wname = wname

    def __str__(self) -> str:
        return f'{self.ppln_id}-{self.comp_id:#08x}'

def read_comp_data(f):
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
    comp_data = {}
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
            comp_data[widget_id] = Component(ppln_id, widget_id, widget_name)
    return comp_data

def read_ipc_data(f, comp_data, args):
    '''Pick ipc tx MOD_INIT_INSTANCE and MOD_LARGE_CONFIG_SET lines
    from log, take time stamp from the first message and the 'done'
    message, and store the difference of to either init_time or
    conf_time in the component table.

    '''
    mod_id = None
    start = None
    for line in f:
        if match_obj := re.search(r" ipc tx (     |reply|done )", line):
            line_split = line.split()
            dt_object = datetime.strptime(line_split[2], "%H:%M:%S.%f")
            secs = dt_object.second + dt_object.minute * 60 + dt_object.hour * 3600
            usecs = secs * 1000000 + dt_object.microsecond
            span_end_pos = match_obj.span()[1]
            # msg_type shoule be either "     ", "reply", or "done "
            msg_type = line[match_obj.span()[0] + 8 : match_obj.span()[1]]
            msg_part = line[span_end_pos:].split()
            primary = int(msg_part[1].split('|')[0], 16)
            extension =  int(msg_part[1].split('|')[1].rstrip(":"), 16)
            if msg_part[2] == "MOD_INIT_INSTANCE" or msg_part[2] == "MOD_LARGE_CONFIG_SET":
                if msg_type == "     ":
                    mod_id = primary & 0xFFFFFF
                    if mod_id == 0:
                        mod_id = None
                        continue
                    start = usecs
                if mod_id == None:
                    continue
                comp = comp_data[mod_id]
                if msg_type == "reply" and args.reply_timings:
                    if msg_part[2] == "MOD_INIT_INSTANCE":
                        print("%s:\tinit reply\t%d us" % (comp.wname, usecs - start))
                    elif msg_part[2] == "MOD_LARGE_CONFIG_SET":
                        print("%s:\tconf reply\t%d us" % (comp.wname, usecs - start))
                    start = usecs
                elif msg_type == "done ":
                    module_id = ""
                    pipeline_id = ""
                    if args.module_id:
                        module_id = "\tmodule id: " + format(mod_id, '#08x')
                    if args.pipeline_id:
                        pipeline_id = "\tpipeline id: " + str(comp.ppln_id)
                    if msg_part[2] == "MOD_INIT_INSTANCE":
                        print("%s:\tinit done\t%d us%s%s" %
			      (comp.wname, usecs - start, module_id, pipeline_id))
                    elif msg_part[2] == "MOD_LARGE_CONFIG_SET":
                        print("%s:\tconf done\t%d us%s%s" %
			      (comp.wname, usecs - start, module_id, pipeline_id))
                    mod_id = None
                    start = None
                    end = None

def parse_args():
    '''Parse command line arguments'''
    parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter,
                                     description=__doc__)
    parser.add_argument('filename')
    parser.add_argument('-r', '--reply-timings', action="store_true", default=False,
                        help='Show time to reply message, "done" time is from "reply"')
    parser.add_argument('-m', '--module-id', action="store_true", default=False,
                        help='Show module id')
    parser.add_argument('-p', '--pipeline-id', action="store_true", default=False,
                        help='Show pipeline id')

    return parser.parse_args()

def main():
    args = parse_args()

    with open(args.filename, 'r', encoding='utf8') as file:
        comp_data = read_comp_data(file)

        file.seek(0)
        read_ipc_data(file, comp_data, args)

if __name__ == "__main__":
    main()
