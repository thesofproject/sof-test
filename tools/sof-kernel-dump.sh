#!/bin/bash

# dump the kernel information from target
reverse_order=${1:-0}
# check whether parameter 1 has the Non-Number
[[ "${reverse_order//[0-9]/}" ]] && echo "$0 parameter 1 just support +N number, N start from 0" && builtin exit 1
# format time stamp output for journalctl command
LC_TIME='en_US.UTF-8'
journalctl --flush
journalctl --boot="$reverse_order" --dmesg --no-pager --no-hostname -o short-precise
