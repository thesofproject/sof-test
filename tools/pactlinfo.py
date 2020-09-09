#!/usr/bin/python3

import re
import os
import argparse

# get the specified sink information from "pactl list sink"
def get_sink(sinkname):
    sinks = os.popen("pactl list sinks").read()
    sink=""
    start = 0
    for line in sinks.splitlines():
        # sink information starts with "Sink #n"
        m = re.match('^Sink #(\d+)', line)
        if m:
            m1 = re.match('^Sink #'+sinkname, line)
            if m1:
                start = 1
            else:
                start = 0
        else:
            if start == 1:
                sink += line+'\n'
    return sink

# get the specified source information from "pactl list source"
def get_source(sourcename):
    sources = os.popen("pactl list sources").read()
    source=""
    start = 0
    for line in sources.splitlines():
        # source information starts with "Source #n"
        m = re.match('^Source #(\d+)', line)
        if m:
            m1 = re.match('^Source #'+sourcename, line)
            if m1:
                start = 1
            else:
                start = 0
        else:
            if start == 1:
                source += line+'\n'
    return source

# get the value of the key in the bulk
# For example, the bulk is the information of a sink, which
# includes "State", "Name", "Driver" and etc information.
# get_value(bulk, "Name: ") will get the name information.
# The "Name: " is the key word format, please refer 'pactl list' for
# more keys format.
# TODO: some informations are splitted into multiple lines. Need to handle
#       this situation if necessary.
def get_value(bulk, key):
    # refine the key to handle the special characters
    schar='\[@_!#$%^&*()<>?/|}{~]'
    for char in schar:
        key=key.replace(char, "\\"+char)

    res = re.findall(key+".*", bulk)
    if res:
        print (re.match("("+key+")(.*)", res[0]).groups(1)[1])
        return(0)
    else:
        return(1)

'''test Main'''
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='parse pactl list information',
                                     add_help=True, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument('--showsinks', action='store_true', default=False, help='show all sinks')
    parser.add_argument('--showsources', action='store_true', default=False, help='show all sources')
    parser.add_argument('--getsinkname', type=int, help='get the appointed sink Name')
    parser.add_argument('--getsourcename', type=int, help='get the appointed source Name')
    parser.add_argument('--getsinkcardname', type=int, help='get the card_name of appointed sink')
    parser.add_argument('--getsourcecardname', type=int, help='get the card_name of appointed source')
    parser.add_argument('--getsinkdeviceclass', type=int, help='get the appointed sink device.class')
    parser.add_argument('--getsourcedeviceclass', type=int, help='get the appointed source device.class')
    parser.add_argument('--getsinkactport', type=int, help='get the appointed sink active port name')
    parser.add_argument('--getsourceactport', type=int, help='get the appointed source active port name')
    parser.add_argument('--getsinkportinfo', help='get the appointed sink port information')
    parser.add_argument('--getsourceportinfo', help='get the appointed source port information')
    parser.add_argument('--version', action='version', version='%(prog)s 1.0')

    ret_args = vars(parser.parse_args())

    if ret_args['showsinks'] is True:
        sinks = os.popen("pactl list short sinks").read()
        for line in sinks.splitlines():
            print (re.match("(\d+)(.*)", line).groups(1)[0])
        exit(0)

    if ret_args['showsources'] is True:
        sources = os.popen("pactl list short sources").read()
        for line in sources.splitlines():
            print (re.match("(\d+)(.*)", line).groups(1)[0])
        exit(0)

    if ret_args.get('getsinkname') is not None:
        sink = ret_args['getsinkname']
        sinkinfo = get_sink(str(sink))
        exit (get_value(sinkinfo, "Name: "))

    if ret_args.get('getsourcename') is not None:
        source = ret_args['getsourcename']
        sourceinfo = get_source(str(source))
        exit (get_value(sourceinfo, "Name: "))

    if ret_args.get('getsinkcardname') is not None:
        sink = ret_args['getsinkcardname']
        sinkinfo = get_sink(str(sink))
        exit (get_value(sinkinfo, "alsa.card_name = "))

    if ret_args.get('getsourcecardname') is not None:
        source = ret_args['getsourcecardname']
        sourceinfo = get_source(str(source))
        exit (get_value(sourceinfo, "alsa.card_name = "))

    if ret_args.get('getsinkdeviceclass') is not None:
        sink = ret_args['getsinkdeviceclass']
        sinkinfo = get_sink(str(sink))
        exit (get_value(sinkinfo, "device.class = "))

    if ret_args.get('getsourcedeviceclass') is not None:
        source = ret_args['getsourcedeviceclass']
        sourceinfo = get_source(str(source))
        exit (get_value(sourceinfo, "device.class = "))

    if ret_args.get('getsinkactport') is not None:
        sink = ret_args['getsinkactport']
        sinkinfo = get_sink(str(sink))
        exit (get_value(sinkinfo, "Active Port: "))

    if ret_args.get('getsourceactport') is not None:
        source = ret_args['getsourceactport']
        sourceinfo = get_source(str(source))
        exit (get_value(sourceinfo, "Active Port: "))

    if ret_args.get('getsinkportinfo') is not None:
        port  = ret_args['getsinkportinfo']
        # get all the sinks
        # TODO: skip the sink ports which belong to unsupported card
        sinkinfo = get_sink(".*")
        exit (get_value(sinkinfo, port+": "))


    if ret_args.get('getsourceportinfo') is not None:
        port  = ret_args['getsourceportinfo']
        # get all the sources
        # TODO: skip the source ports which belong to unsupported card
        sourceinfo = get_source(".*")
        exit (get_value(sourceinfo, port+": "))

    exit(0)
