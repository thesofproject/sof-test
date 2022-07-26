#!/bin/bash

# FIXME: replace calls to this complex and buggy script with much
# simpler calls to `journalctl -k` which has a slightly different (but
# customizable) format; a few extra messages and most importantly: never
# rotates and never loses the first 'Linux version' line.

# dump the kernel information from target
last_order=${1:-0}
# check whether parameter 1 has the Non-Number
[[ "${last_order//[0-9]/}" ]] && echo "$0 parameter 1 just support +N number, N start from 0" && builtin exit 1
last_order=$[ $last_order + 1 ]
log_file=${2:-"/var/log/kern.log"}
# check whether target file exists
[[ ! -f "$log_file" ]] && echo "$0 parameter 2 $log_file does not exist" && builtin exit 1
# load helper script
which sof-get-kernel-line.sh 2>&1 1>/dev/null
if [ $? -eq 0 ]; then
    kernel_line_script="sof-get-kernel-line.sh"
else
    cd $(dirname $0)
    kernel_line_script=$PWD/sof-get-kernel-line.sh
    cd $OLDPWD
fi
declare -a line_lst
# here line lst to keep 2 value, [0] is target line, [1] is end line
# if target is last one, so will cut content form [0] -> file end
# if target is second last, so will cut content from [0] -> [1]
line_lst=($($kernel_line_script $log_file|tail -n $last_order|awk '{print $1;}'))
# sof-get-kernel-line.sh dump nothing
[[ ! "${line_lst[0]}" ]] && echo "$0 without catch system boot keyword" && builtin exit 1
# check target is last one
if [ ! "${line_lst[1]}" ];then
    # tr '\0' ' ' to fix warning message: "command substitution: ignored null byte in input"
    tail -n +${line_lst[0]} $log_file|tr '\0' ' '|cut -f5- -d ' '
else
    line_count=$[ ${line_lst[1]} - ${line_lst[0]} ]
    # tr '\0' ' ' to fix warning message: "command substitution: ignored null byte in input"
    tail -n +${line_lst[0]} $log_file|tr '\0' ' '|head -n $line_count|cut -f5- -d ' '
fi
