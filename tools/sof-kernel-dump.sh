#!/bin/bash

# dump the kernel information from target
boot_number=${1:-0}

# format time stamp output for journalctl command
LC_TIME='en_US.UTF-8'
journalctl --boot="$boot_number" --dmesg --no-pager --no-hostname -o short-precise
