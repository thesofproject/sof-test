#!/bin/bash

begin_time=${1:-0}
declare err_str ignore_str project_key
err_str="error|failed|timed out|panic|oops"
ignore_str="error: debugfs write failed to idle -16|error: status|iteration [01]"
project_key="sof-audio"

[[ ! "$err_str" ]] && {
    echo "Missing error keyword list"
    builtin exit 0
}

if [ "X$begin_time" == "X0" ]; then
    cmd="dmesg"
else
    date -d "$begin_time" +'%F %T' > /dev/null || {
        echo "Error parameter for date: $begin_time"
        echo "Support date format: date +'%F %T'"
        builtin exit 0
    }
    journalctl --flush
    cmd="journalctl --dmesg --no-pager --no-hostname -o short-precise --since='$begin_time'"
fi

if [ "$ignore_str" ]; then
    err=$(eval "$cmd"|grep 'Call Trace' -A5 -B3)$(eval "$cmd" | grep $project_key | grep -E "$err_str"|grep -vE "$ignore_str")
else
    err=$(eval "$cmd"|grep 'Call Trace' -A5 -B3)$(eval "$cmd" | grep $project_key | grep -E "$err_str")
fi

if [ "$err" ]; then
    echo "$(date -u '+%F %T %Z') [ERROR] Caught dmesg error"
    echo "===========================>>"
    echo "$err"
    echo "<<==========================="
    builtin exit 1
fi

builtin exit 0
