#!/bin/bash

##
## Case Name: verify-kernel-boot-log
## Preconditions:
##    N/A
## Description:
##    Check kernel boot log, and see if there is any errors
## Case step:
##    1. Disable kernel check point and check kernel log from kernel boot
## Expect result:
##    No error found in kernel boot log
##

set -e

# source from the relative path of current folder
# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

main()
{
    func_opt_parse_option "$@"
    disable_kernel_check_point

    print_module_params

    ntp_check

    sof-kernel-log-check.sh
}

ntp_check()
{
    # Check this device time is NTP Synchronized
    if check_ntp_sync; then
        printf '\nTime Check: NTP Synchronized\n'
    else
        timedatectl show
        # try to disable/enable NTP once, this will trigger ntp sync twice,
        # before stopping ntp and after enabling ntp.
        re_enable_ntp_sync

        if check_ntp_sync; then
            printf '\nTime Check: NTP Synchronized after re-enabling ntp sync\n'
        else
            # If NTP is not synchronized, let this test fail
            die "Time Check: NTP NOT Synchronized"
        fi
    fi
}

main "$@"
