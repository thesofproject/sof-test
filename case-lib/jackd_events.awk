#!/usr/bin/gawk -f

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.

# Process `jackd` output to count XRun's.

/JackEngine::XRun: client = jack_delay/ {
  xrun_cnt+=1
}

END {
  printf("\"xruns\":%d", xrun_cnt)
  fflush()
}
