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
# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../case-lib/lib.sh"

func_opt_parse_option "$@"

if alias |grep -q 'Sub-Test' ;then
    cmd="dmesg"
else
    # hijack DMESG_LOG_START_LINE which refer dump kernel log in exit function
    DMESG_LOG_START_LINE=$(sof-get-kernel-line.sh|tail -n 1 |awk '{print $1;}')
    cmd="sof-kernel-dump.sh"
fi

dlogi "Checking SOF Firmware load info in kernel log"
$cmd | grep -q "sof-audio.*Firmware.*version" && {
    # dump the version info and ABI info
    $cmd | grep "Firmware info" -A1
    # dump the debug info
    $cmd | grep "Firmware debug build" -A3
    exit 0
}

die "Cannot find the sof audio version"
