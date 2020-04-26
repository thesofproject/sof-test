#!/bin/bash

begin_line=${1:-1}
declare err_str ignore_str project_key
err_str="error|failed|timed out|panic|oops"
ignore_str="error: debugfs write failed to idle -16|error: status|iteration [01]"
project_key="sof-audio"

[[ ! "$err_str" ]] && echo "Missing error keyword list" && exit 0
# dmesg KB size buffer size
#dmesg_config_define=$(awk -F '=' '/CONFIG_LOG_BUF_SHIFT/ {print $2;}' /boot/config-$(uname -r))
#dmesg_buffer_size=$( echo $(( (1<<$dmesg_config_define) / 1024 )) )
# kernel file log buffer size
#kernel_buffer_size=$(du -k /var/log/kern.log |awk '{print $1;}')
# now decide using which to catch the kernel log
#[[ $kernel_buffer_size -lt $dmesg ]] && cmd="dmesg" || cmd="sed -n '$begin_line,\$p' /var/log/kern.log"

# confirm begin_line is number, if it is not the number, direct using dmesg
[[ "${begin_line//[0-9]/}" ]] && begin_line=0
[[ "$begin_line" -eq 0 ]] && cmd="dmesg" || cmd="sed -n '$begin_line,\$p' /var/log/kern.log"

#echo "run $0 with parameter '$*' for check kernel message error"

if [ "$ignore_str" ]; then
    err=$(eval "$cmd"|grep 'Call Trace' -A5 -B3)$(eval "$cmd" | grep "$project_key" | grep -E "$err_str"|grep -vE "$ignore_str")
else
    err=$(eval "$cmd"|grep 'Call Trace' -A5 -B3)$(eval "$cmd" | grep "$project_key" | grep -E "$err_str")
fi

if [ "$err" ]; then
    echo "$(date -u '+%Y-%m-%d %T %Z') [ERROR] Caught dmesg error"
    echo "===========================>>"
    echo "$err"
    echo "<<==========================="
    # exclude none alsa trace, but still print trace message
    snd_trace=$(echo "$err" | grep "snd")
    [ -z "$snd_trace" ] && builtin exit 0
    builtin exit 1
fi

builtin exit 0
