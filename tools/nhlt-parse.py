#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2020 Intel Corporation. All rights reserved.
#
# usage: nhlt-parse.py <nhtl-dump>
#
# examples:
#   cat /sys/firmware/acpi/tables/NHLT >nhtl.bin
#   ./nhtl-parse.py nhtl.bin
#
# references:
#  - https://01.org/sites/default/files/595976_intel_sst_nhlt.pdf

from collections import namedtuple
import struct
import sys

if len(sys.argv) == 1:
    infile = '/sys/firmware/acpi/tables/NHLT'
else:
    infile = sys.argv[1]

f = open(infile, 'rb')

record = f.read()

Link = namedtuple('Link', 'DescriptorLength LinkType InstanceID VendorID DeviceID RevID SubsystemID DevType Direction VirtualBusId')

link_types = { 0:'HDA', 1:'DSP', 2:'PDM', 3:'SSP', 4:'Reserved4', 5:'SoundWire' }

# skip ACPI table header
p = 36
n_endpoints = struct.unpack('<B', record[p:p+1])

p = p+1

print('NHLT %u endpoints' % n_endpoints)

dmic_count = 0

for i in range(0,n_endpoints[0]):
    # ENDPOINT_DESCRIPTOR
    ffmt = '<IBBHHHIBBB'
    fsize = struct.calcsize(ffmt)
    endpoint_descriptor = record[p:p+fsize]
    link = Link._make(struct.unpack(ffmt, endpoint_descriptor))
    link_type = link._asdict()['LinkType']
    print(link)
    print('NHLT link type %s' % link_types[link_type])
    if link_type == 2:
        dmic_count += 1
    p = p + fsize

    # SPECIFIC_CONFIG
    ffmt = '<I'
    fsize = struct.calcsize(ffmt)
    cap_size = struct.unpack(ffmt, record[p:p+fsize])
    print('NHLT SPECIFIC_CONFIG size %u' % cap_size)
    p = p + cap_size[0] + fsize

    # FORMATS_CONFIG
    ffmt = '<B'
    fsize = struct.calcsize(ffmt)
    n_formats = struct.unpack(ffmt, record[p:p+fsize])
    print('NHLT FORMAT CONFIGS %u' % n_formats)
    p = p + cap_size[0] + fsize

print('NHTL: %d dmics described' % dmic_count)
