#!/bin/bash

##
## Case Name: verify-sof-firmware-load
## Description:
##    Check if the SOF fw loaded successfully in dmesg
## Case step:
##    Check dmesg to search fw load info
## Expect result:
##    Get fw version info in dmesg
##    sof-audio-pci 0000:00:0e.0: Firmware info: version 1:1:0-e5fe2
##    sof-audio-pci 0000:00:0e.0: Firmware: ABI 3:11:0 Kernel ABI 3:11:0
##

# source from the relative path of current folder
source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

func_opt_parse_option "$@"

if [ ! "$(alias |grep 'Sub-Test')" ];then
    # hijack CASE_KERNEL_START_TIME which refer dump kernel log in exit function
    unset CASE_KERNEL_START_TIME
    cmd="sof-kernel-dump.sh"
else
    cmd="dmesg"
fi

dlogi "Checking SOF Firmware load info in kernel log"
if [[ $(eval $cmd | grep "] sof-audio.*version") ]]; then
    # dump the version info and ABI info
    eval $cmd | grep "Firmware info" -A1
    # dump the debug info
    eval $cmd | grep "Firmware debug build" -A3
    exit 0
else
    dloge "Cannot find the sof audio version" && exit 1
fi
