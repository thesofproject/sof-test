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

# hijack DMESG_LOG_START_LINE to dump kernel from file start is not Sub-Test
# TODO: clean up Sub-Test feature
alias | grep -q 'Sub-Test' || DMESG_LOG_START_LINE=$(sof-get-kernel-line.sh | tail -n 1 | awk '{print $1;}' )

# flush and sync journalctl logs
sudo journalctl --sync --flush || true

cmd="journalctl -k -q --no-pager --utc --output=short-monotonic --no-hostname"

dlogi "Checking SOF Firmware load info in kernel log"
if $cmd | grep -q " sof-audio.*Firmware.*version"; then
    # dump the version info and ABI info
    $cmd | grep "Firmware info" -A1 | head -n 12
    # dump the debug info
    $cmd | grep "Firmware debug build" -A3 | head -n 12
    exit 0
else
    journalctl -k -q --no-pager --utc --output=short-monotonic --no-hostname --lines 50 || true
    printf ' ------\n  debugging with systemd journalctl  \n ---- \n'
    systemctl status systemd-journald* || true
    die "Cannot find the sof audio version"
fi
