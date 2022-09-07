#!/bin/bash

set -e

##
## Case Name: verify-sof-firmware-load
## Description:
##    Check if the SOF fw loaded successfully at least once in the whole
##    kernel logs. This test can PASS after unloading the drivers!
## Case step:
##    Check kernel logs to search fw load info
## Expect result:
##    'sof boot complete' found at least once in the kernel logs
##

# source from the relative path of current folder
# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

func_opt_parse_option "$@"

disable_kernel_check_point

start_test

cmd="kernel_logger_cmd"

dlogi "Checking SOF Firmware load info in kernel log"
if sof_firmware_boot_complete; then

    # Show messages again but with wallclock timestamps
    # that can be matched with the ktimes just printed.
    sof_firmware_boot_complete --output=short

    # On some systems 'firmware boot complete' can be printed again on
    # every resume from D3. These versions are printed only when the
    # kernel driver is loaded.
    grep_firmware_info_in_logs
    exit 0

else # failed, show some logs

    printf ' ------\n  Check journalctl status: \n ---- \n'
    systemctl --no-pager status systemd-journald* || true
    kernel_logger_cmd --lines 50 || true

    die "Cannot find any 'sof boot complete' message in logs since boot time"
fi
