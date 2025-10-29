#!/usr/bin/gawk -f

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.

BEGIN {
  IGNORECASE = 1
  found = 0

  # If show_capture_controls is set, use capture control display mode
  capture_mode = show_capture_controls ? 1 : 0
}

# Original functionality: Extract control state by name
!capture_mode && /name='/ {
  if (tolower($0) ~ tolower(name)) found = 1
  else found = 0
}

!capture_mode && found && /: values=/ {
  sub(/^.*: values=/, "", $0)
  print $0
  found = 0
}

# New functionality: Show capture controls
capture_mode && /^numid=/ {
  n=$0
  show = tolower($0) ~ /capture/
  capture_found = 0
}

capture_mode && /type=BOOLEAN/ {
  t = $0
  if (show) capture_found = 1
}

capture_mode && /: values=/ && capture_found {
  print n
  print t
  print $0
  capture_found = 0
}
