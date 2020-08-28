#!/bin/bash

begin_line=${1:-1}
declare err_str ignore_str project_key
err_str="error|failed|timed out|oops"

# TODO explain
ignore_str="$ignore_str"'|error: debugfs write failed to idle -16'

# Realtek codecs thrown an error on startup, checking with Realtek
# Possible fix - https://github.com/thesofproject/linux/pull/1984
ignore_str="$ignore_str"'|Parity error detected'

# CML Helios known issue related with xhci_hcd
# https://bugzilla.kernel.org/show_bug.cgi?id=202541
ignore_str="$ignore_str"'|xhci_hcd 0000:00:14.0: WARN Set TR Deq Ptr cmd failed due to incorrect slot or ep state'

# CML Mantis occasionally throws Intel(R) Management Engine Interface(mei) errors
# https://unix.stackexchange.com/questions/109294/mei-00000016-0-init-hw-failure
ignore_str="$ignore_str"'|mei_me 0000:00:16.0: wait hw ready failed'
ignore_str="$ignore_str"'|mei_me 0000:00:16.0: hw_start failed ret = -62'

# CML Mantis has DELL touchpad i2c error on suspend/resume
ignore_str="$ignore_str"'|i2c_designware i2c_designware.0: controller timed out'
ignore_str="$ignore_str"'|i2c_hid i2c-DELL0955:00: failed to change power setting'
ignore_str="$ignore_str"'|PM: Device i2c-DELL0955:00 failed to resume async: error -110'

# GLK i2c SRM failed to lock, found while running check-playback-all-formats.sh
# https://github.com/thesofproject/sof-test/issues/348
ignore_str="$ignore_str"'|da7219 i2c-DLGS7219:00: SRM failed to lock'

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
    err=$(eval $cmd|grep 'Call Trace' -A5 -B3)$(eval $cmd | grep -E "$err_str"|grep -vE "$ignore_str")
else
    err=$(eval $cmd|grep 'Call Trace' -A5 -B3)$(eval $cmd | grep -E "$err_str")
fi

if [ "$err" ]; then
    echo `date -u '+%Y-%m-%d %T %Z'` "[ERROR]" "Caught dmesg error"
    echo "===========================>>"
    echo "$err"
    echo "<<==========================="
    builtin exit 1
fi

builtin exit 0
