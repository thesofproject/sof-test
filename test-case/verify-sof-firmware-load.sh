#!/bin/bash

set -e

##
## Case Name: verify-sof-firmware-load
## Description:
##    Check if the SOF fw loaded successfully in the kernel logs
## Case step:
##    Check kernel logs to search fw load info
## Expect result:
##    Get fw version info in dmesg
##    sof-audio-pci 0000:00:0e.0: Firmware info: version 1:1:0-e5fe2
##    sof-audio-pci 0000:00:0e.0: Firmware: ABI 3:11:0 Kernel ABI 3:11:0
##

# source from the relative path of current folder
# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

func_opt_parse_option "$@"

setup_kernel_check_point

( set +x
    if [ "$SOF_VERSION_CHECK" = 'none' ]; then
        printf '$''SOF_VERSION_CHECK=none, skipping verify-sof-firmware-load.sh\n'
        exit 2
    fi
)

cmd="journalctl_cmd"

dlogi "Checking SOF Firmware load info in kernel log"
if $cmd | grep -q " sof-audio.*Firmware.*version"; then
    # dump the version info and ABI info
    $cmd | grep "Firmware info" -A1 | head -n 12
    # dump the debug info
    $cmd | grep "Firmware debug build" -A3 | head -n 12
    exit 0

else # failed, show some logs

    journalctl_cmd --lines 50 || true
    printf ' ------\n  Check journalctl status: \n ---- \n'
    systemctl --no-pager status systemd-journald* || true
    die "Cannot find the sof audio version"
fi
