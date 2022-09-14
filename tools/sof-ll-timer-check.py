#!/usr/bin/env python3

'''Script to analyze performance data in SOF FW log output'''

import sys
import re
import json
from statistics import median

# allowed error margin before error is raised for
# lower observed performance (1.05 -> 5% difference
# required to raise error)
AVG_ERROR_MARGIN = 1.05

max_vals = []
avg_vals = []
overruns = 0

f = open(sys.argv[1])

for line in f:
    m = re.search('.*ll timer avg ([0-9]*), max ([0-9]*), overruns ([0-9]*)', line)
    if m:
        avg_vals.append(int(m.group(1)))
        max_vals.append(int(m.group(2)))
        overruns += int(m.group(3))

median_avg_vals = median(avg_vals)
print("Measurements:\t\t%d" % len(avg_vals))
print("Median avg reported:\t%d" % median_avg_vals)
print("Median max reported:\t%d" % median(max_vals))
print("Highest max reported:\t%d" % max(max_vals))

if overruns:
    print("ERROR: %s overruns detected" % overruns, file=sys.stderr)
    sys.exit(-1)

if len(sys.argv) < 4:
    print("No reference data for key '%s', unable to check performance against reference")
    sys.exit(0)

median_avg_ref = None
dbfile = open(sys.argv[3])
ref_key = sys.argv[2]
ref_data_all = json.load(dbfile)

for ref in ref_data_all:
    if ref["test-key"] == ref_key:
        median_avg_ref = ref["ll-timer-avg"]
        break

if not median_avg_ref:
    print("No reference data for key '%s', unable to check performance against reference" % ref_key)
    sys.exit(0)

median_avg_ref_w_margin = median_avg_ref * AVG_ERROR_MARGIN
if median_avg_vals > median_avg_ref_w_margin:
    print("ERROR: ll-timer-avg median %d over threshold %d (%d without margin)" % (median_avg_vals, median_avg_ref_w_margin, median_avg_ref), file=sys.stderr)
    sys.exit(-1)
