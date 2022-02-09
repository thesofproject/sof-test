#!/bin/bash

set -e

##
## Case Name: verify-sof-firmware-load
## Description:
##    Check if /sys/kernel/debug/sof/fw_version exists
## Expect result:
##    /sys/kernel/debug/sof/fw_version exists
##
##    When found, also show the firmware version(s) found in the kernel logs
##    sof-audio-pci 0000:00:0e.0: Firmware info: version 1:1:0-e5fe2
##    sof-audio-pci 0000:00:0e.0: Firmware: ABI 3:11:0 Kernel ABI 3:11:0
##

# source from the relative path of current folder
# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

func_opt_parse_option "$@"

# We don't use KERNEL_CHECKPOINT in this test. FIXME: (re)move this line
# after checking how this line interferes with other tests invoking us
# (e.g.: load-unload test)
setup_kernel_check_point

cmd="journalctl_cmd"

# TODO: move this to main()
dlogi "Showing all SOF Firmware version(s) in kernel log (mind the timestamps!)"
if $cmd | grep -q " sof-audio.*Firmware.*version"; then
    # dump the version info and ABI info
    $cmd | grep "Firmware info" -A1 | head -n 12
    # dump the debug info
    $cmd | grep "Firmware debug build" -A3 | head -n 12
fi

main()
{
    local fw_version=/sys/kernel/debug/sof/fw_version

    if sudo test -e "$fw_version"; then
        printf '  ------ %s found  ----\n' "$fw_version"
        exit 0
    fi

    # failed, show some logs
    journalctl_cmd --lines 50 || true
    printf ' ------\n  Check journalctl status: \n ---- \n'
    systemctl --no-pager status systemd-journald* || true
    die "Cannot find ${fw_version}"
}

main "$@"
