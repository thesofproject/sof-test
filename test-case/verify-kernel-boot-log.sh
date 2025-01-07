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

trap 'boot_log_exit_handler $?' EXIT

boot_log_exit_handler()
{
    local exit_code=$1

    # This script is normally run first and immediately after boot. 'max_lines' protects
    # storage in case it's not (and debug logs are on!). Long logs also make the user
    # interface unresponsive, see example in (unrelated)
    # https://github.com/thesofproject/sof/issues/8761.
    #
    # A typical boot log with SOF debug is 3000 lines, see more numbers in
    # detect_log_flood() comments below. Double that to be on the safe side.
    local max_lines=6000

    # For issues with sound daemons, display, USB, network, NTP, systemd, etc.
    journalctl --boot  | head -n "$max_lines" > "$LOG_ROOT"/boot_log.txt
    # More focused
    journalctl --dmesg | head -n "$max_lines" > "$LOG_ROOT"/dmesg.txt

    print_test_result_exit "$exit_code"
}

main()
{
    printf 'System booted at: '; uptime -s
    journalctl -b | head -n 3

    func_opt_parse_option "$@"
    disable_kernel_check_point

    print_module_params

    # print the BIOS version
    sudo dmidecode --type 0

    show_daemons_session_display

    wait_is_system_running --system
    [ "$(id -un)" = root ] ||
        wait_is_system_running --user

    detect_log_flood

    ntp_check

    platform=$(sof-dump-status.py -p)
    case "$platform" in
        lnl)
           # Example kept for convenience
           # skip_test "internal #99: missing GPU firmware and others on $platform"
            ;;
    esac

    sof-kernel-log-check.sh

    dmic_switch_present
}

wait_is_system_running()
{
    local manager="$1" # --user or --system
    local wait_secs=30 ret=0
    local cmd=(systemctl "$manager" --wait is-system-running)

    printf '%s\n' "${cmd[*]}"
    timeout -k 5 "$wait_secs" "${cmd[@]}" || ret=$?

    if [ $ret = 0 ]; then return 0; fi

    if [ $ret = 124 ]; then
        dloge "$0 timed out waiting $wait_secs seconds for ${cmd[*]}"
    fi
    (   set +e; set -x
        systemctl "$manager" --no-pager --failed
        systemctl "$manager" | grep -v active
        systemctl "$manager" is-system-running

        # This subshell is best-effort diagnostics: don't let the exit
        # status of the previous command(s) affect the test result
        true
    )
    die "Some services are not running correctly"
}

# See:
# - https://github.com/thesofproject/sof/pull/8740
# - https://github.com/thesofproject/sof-test/issues/1176
# - Internal Intel issue #559
dmic_switch_present()
{
    # No "DMIC Raw" => no switch => success!
    arecord -l | grep -i 'sof.*dmic.*raw' || return 0

    (set -x
     # name= is hardcoded in /usr/share/alsa/ucm2/*
     # This returns a non-zero error status on failure
     switch=$(aplay -l | head -2 | tail -1 | awk '{print $3}')
     amixer -c "$switch" cget name='Dmic0 Capture Switch'
    )
}


show_daemons_session_display()
{
    ( set +e

    # '*session*' and 'gvfs-*' shows whether someone is currently logged
    # in some GNOME or other session or not because Audio daemons differ
    # in different cases, see commit 7ffd738bc81d. Some audio daemons
    # can also linger after logging out. This also shows whether X11 or
    # Wayland runs - or nothing at all!  The lack of gnome-session-*
    # displayed here can be due a switch to lightdm or to
    # AutomaticLogin* not being enabled in /etc/gdm3/custom.conf.  For
    # more see https://github.com/thesofproject/sof-test/discussions/964
    systemctl list-units '*dm*.service'; printf '\n'
    systemctl list-unit-files --user '*pipewire*' '*audio*'
    printf '\n'
    # On some Ubuntu 22 systems, the "--all" option triggers the pager. No idea why.
    systemctl --no-pager list-units --user --all '*session*' '*pipewire*' '*audio*' 'gvfs-*'
    printf '\n'

    # See https://github.com/thesofproject/sof-test/discussions/964
    # and https://github.com/thesofproject/linux/issues/4861
    (set -x
     # This is very hit-and-miss, it notably fails when the $XAUTHORITY file is placed in
     # a session-specific, /run/user/ tmpfs that cannot be seen over ssh (or from any
     # other session). Sometimes this shows XWAYLAND.
     # As of April 2024 there does not seem to be any Wayland equivalent for `xrandr`
     for d in 0 1024; do
         DISPLAY=:"$d"  timeout -k 3 5 xrandr --listmonitors
     done

     ls -l /sys/class/drm/
     set +x # can't use set -x because of the crazy "sudo()" in hijack.sh
     sudo ls -C /sys/kernel/debug/dri/0/
    )
    printf '\n'
    # DRM_XE keeps using i915 code for display, so this will hopefully keep working.
    sudo grep -B3 -A1 -i -e connected -e enabled -e active -e audio -e connected \
         /sys/kernel/debug/dri/0/i915_display_info
    printf '\n'

    ( set -x; gsettings get org.gnome.desktop.session idle-delay )
    printf '\n'
    )
}


# Flood usually from gdm3 but keep this function generic
#   https://github.com/thesofproject/sof-test/discussions/998
detect_log_flood()
{
    local recent_lines
    recent_lines=$(sudo journalctl -b --since='1 minute ago'  | wc -l)

    # Finding a good threshold is difficult because we want this test to
    # work both right after boot but also long after.
    #
    # - A normal boot with sof debug prints roughly ~3,000 lines.
    # - The gdm3 infinite crash loop #998 floods ~500 lines/second
    #   but only after a ~10 seconds delay.
    # - With Wayland, the similar crash loop floods only ~50 lines/second.
    #   BUT,  it does mark
    #     `systemctl --user status org.gnome.Shell@wayland.service`
    #   as "FAILED" after a couple minutes trying so there's no risk of
    #   missing the problem.

    # If this has to change in the future then 'max_lines' above should
    # probably be updated too.
    if [ "$recent_lines" -lt 6000 ]; then
        return 0
    fi

    sudo journalctl -b --no-pager --lines=300
    printf '\n\n'
    sudo journalctl -b -p 3
    printf '\n\n'
    sudo du -sk /var/log/* | sort -nr | head -n 10
    printf '\n\n'

    die 'log flood detected!'
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

        # In normal case, it will trigger NTP sync immediately,
        # but expect some network delay.
        sleep 5
        if check_ntp_sync; then
            printf '\nTime Check: NTP Synchronized after re-enabling ntp sync\n'
        else
            # If NTP is not synchronized, let this test fail
            die "Time Check: NTP NOT Synchronized"
        fi
    fi
}

main "$@"
