#!/bin/bash

# dump line number + kernel version
# for example:
# 22 4.15.0-74-generic
# 1092 4.15.0-74-generic
# 2156 4.15.0-74-generic
# 3246 4.15.0-74-generic
log_file=${1:-"/var/log/kern.log"}
[[ ! -f $log_file ]] && builtin exit 1
bootup_keyword='\[    0.000000\] Linux version '
grep -na "$bootup_keyword" $log_file|awk -F ':' '{print $1 $(NF-2);}'|sed "s/$bootup_keyword//g"|awk '{print $1, $2;}'
