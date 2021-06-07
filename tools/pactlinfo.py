#!/usr/bin/env python3

''' This is a helper tool to analysis pactl cmd '''

import re
import os
import sys
import argparse

# get the specified sink information from "pactl list sink"
def get_sink(sinkname):
    ''' extract the appointed sink information '''
    _sinks = os.popen("pactl list sinks").read()
    _sink = ""
    start = 0
    for sinkline in _sinks.splitlines():
        # sink information starts with "Sink #n"
        mod = re.match(r'^Sink #(\d+)', sinkline)
        if mod:
            modst = re.match('^Sink #'+sinkname, sinkline)
            if modst:
                start = 1
            else:
                start = 0
        else:
            if start == 1:
                _sink += sinkline+'\n'
    return _sink

# get the specified source information from "pactl list source"
def get_source(sourcename):
    ''' extract the appointed source information '''
    _sources = os.popen("pactl list sources").read()
    _source = ""
    start = 0
    for srcline in _sources.splitlines():
        # source information starts with "Source #n"
        mod = re.match(r'^Source #(\d+)', srcline)
        if mod:
            modst = re.match('^Source #'+sourcename, srcline)
            if modst:
                start = 1
            else:
                start = 0
        else:
            if start == 1:
                _source += srcline+'\n'
    return _source

# get the value of the key in the bulk
# For example, the bulk is the information of a sink, which
# includes "State", "Name", "Driver" and etc information.
# get_value(bulk, "Name: ") will get the name information.
# The "Name: " is the key word format, please refer 'pactl list' for
# more keys format.
# TODO: some informations are splitted into multiple lines. Need to handle
#       this situation if necessary.
def get_value(bulk, key):
    ''' get the value of the "key" from the bulk info '''
    # refine the key to handle the special characters
    schar = r'\[@_!#$%^&*()<>?/|}{~]'
    for char in schar:
        key = key.replace(char, "\\"+char)

    res = re.findall(key+".*", bulk)
    if res:
        print(re.match("("+key+")(.*)", res[0]).groups(1)[1])
        return 0

    return 1

if __name__ == '__main__':
    PARSER = argparse.ArgumentParser(description='parse pactl list information',
                                     add_help=True, formatter_class=argparse.RawTextHelpFormatter)
    PARSER.add_argument('--showsinks',
                        action='store_true', default=False, help='show all sinks')
    PARSER.add_argument('--showsources',
                        action='store_true', default=False, help='show all sources')
    PARSER.add_argument('--getsinkname', type=int,
                        help='get the appointed sink Name')
    PARSER.add_argument('--getsourcename', type=int,
                        help='get the appointed source Name')
    PARSER.add_argument('--getsinkcardname', type=int,
                        help='get the card_name of appointed sink')
    PARSER.add_argument('--getsourcecardname', type=int,
                        help='get the card_name of appointed source')
    PARSER.add_argument('--getsinkdeviceclass', type=int,
                        help='get the appointed sink device.class')
    PARSER.add_argument('--getsourcedeviceclass', type=int,
                        help='get the appointed source device.class')
    PARSER.add_argument('--getsinkactport', type=int,
                        help='get the appointed sink active port name')
    PARSER.add_argument('--getsourceactport', type=int,
                        help='get the appointed source active port name')
    PARSER.add_argument('--getsinkportinfo',
                        help='get the appointed sink port information')
    PARSER.add_argument('--getsourceportinfo',
                        help='get the appointed source port information')
    PARSER.add_argument('--version', action='version', version='%(prog)s 1.0')

    ret_args = PARSER.parse_args()

    if ret_args.showsinks is True:
        SINKS = os.popen("pactl list short sinks").read()
        for line in SINKS.splitlines():
            print(re.match(r"(\d+)(.*)", line).groups(1)[0])
        sys.exit(0)

    if ret_args.showsources is True:
        SOURCES = os.popen("pactl list short sources").read()
        for line in SOURCES.splitlines():
            print(re.match(r"(\d+)(.*)", line).groups(1)[0])
        sys.exit(0)

    if ret_args.getsinkname is not None:
        SINK = ret_args.getsinkname
        SINKINFO = get_sink(str(SINK))
        sys.exit(get_value(SINKINFO, "Name: "))

    if ret_args.getsourcename is not None:
        SOURCE = ret_args.getsourcename
        SOURCEINFO = get_source(str(SOURCE))
        sys.exit(get_value(SOURCEINFO, "Name: "))

    if ret_args.getsinkcardname is not None:
        SINK = ret_args.getsinkcardname
        SINKINFO = get_sink(str(SINK))
        sys.exit(get_value(SINKINFO, "alsa.card_name = "))

    if ret_args.getsourcecardname is not None:
        SOURCE = ret_args.getsourcecardname
        SOURCEINFO = get_source(str(SOURCE))
        sys.exit(get_value(SOURCEINFO, "alsa.card_name = "))

    if ret_args.getsinkdeviceclass is not None:
        SINK = ret_args.getsinkdeviceclass
        SINKINFO = get_sink(str(SINK))
        sys.exit(get_value(SINKINFO, "device.class = "))

    if ret_args.getsourcedeviceclass is not None:
        SOURCE = ret_args.getsourcedeviceclass
        SOURCEINFO = get_source(str(SOURCE))
        sys.exit(get_value(SOURCEINFO, "device.class = "))

    if ret_args.getsinkactport is not None:
        SINK = ret_args.getsinkactport
        SINKINFO = get_sink(str(SINK))
        sys.exit(get_value(SINKINFO, "Active Port: "))

    if ret_args.getsourceactport is not None:
        SOURCE = ret_args.getsourceactport
        SOURCEINFO = get_source(str(SOURCE))
        sys.exit(get_value(SOURCEINFO, "Active Port: "))

    if ret_args.getsinkportinfo is not None:
        PORT = ret_args.getsinkportinfo
        # get all the sinks
        # TODO: skip the sink ports which belong to unsupported card
        SINKINFO = get_sink(".*")
        sys.exit(get_value(SINKINFO, PORT+": "))


    if ret_args.getsourceportinfo is not None:
        PORT = ret_args.getsourceportinfo
        # get all the sources
        # TODO: skip the source ports which belong to unsupported card
        SOURCEINFO = get_source(".*")
        sys.exit(get_value(SOURCEINFO, PORT+": "))

    sys.exit(0)
