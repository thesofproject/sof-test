#!/usr/bin/gawk -f

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.

BEGIN {
  IGNORECASE = 1
  found = 0
}

# Detect the line with the control name
/name='/ {
  if (tolower($0) ~ tolower(name)) found = 1
  else found = 0
}

# When in a matching section, extract the "values" field
found && /: values=/ {
  sub(/^.*: values=/, "", $0)
  print $0
  found = 0
}
