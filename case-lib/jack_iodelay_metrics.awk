#!/usr/bin/gawk -f

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.

# Process `jack_iodelay` output to extract latency measurements,
# and calculate some general statistics: min, max, avg, stddev.
# The resulting output is a json dictionary.

@include "lib.awk"

/^[ ]*[0-9.]+ frames[ ]+[0-9.]+ ms total roundtrip latency/ {
  sum_frames+=$1
  sum_ms+=$3
  latency_frames[NR]=$1
  latency_ms[NR]=$3
}

END {
  if (length(latency_frames) !=0 && length(latency_ms) != 0) {
    printf("\"metric_name\":\"roundtrip latency\", ")
    printf("\"probes\":%d, ", length(latency_frames))
    printf("\"avg_frames\":%0.3f, ", (length(latency_frames) ? sum(latency_frames) / length(latency_frames) : 0))
    printf("\"min_frames\":%0.3f, \"max_frames\":%0.3f, ", min(latency_frames), max(latency_frames))
    printf("\"avg_ms\":%0.3f, ", (length(latency_ms) ? sum(latency_ms) / length(latency_ms) : 0))
    printf("\"min_ms\":%0.3f, \"max_ms\":%0.3f, ", min(latency_ms), max(latency_ms))
    printf("\"stdev_frames\":%0.6f, \"stdev_ms\":%0.6f", stddev(latency_frames), stddev(latency_ms))
    fflush()
  }
}
