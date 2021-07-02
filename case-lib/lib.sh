#!/bin/bash

# get test-case information
SCRIPT_HOME="$(dirname "${BASH_SOURCE[0]}")"
# get test-case parent folder name
SCRIPT_HOME=$(cd "$SCRIPT_HOME/.." && pwd)
# shellcheck disable=SC2034 # external script can use it
SCRIPT_NAME="$0"  # get test-case script load name
# shellcheck disable=SC2034 # external script can use it
SCRIPT_PRAM="$*"  # get test-case parameter

# Source from the relative path of current folder
# shellcheck source=case-lib/config.sh
source "$SCRIPT_HOME/case-lib/config.sh"
# shellcheck source=case-lib/opt.sh
source "$SCRIPT_HOME/case-lib/opt.sh"
# shellcheck source=case-lib/logging_ctl.sh
source "$SCRIPT_HOME/case-lib/logging_ctl.sh"
# shellcheck source=case-lib/pipeline.sh
source "$SCRIPT_HOME/case-lib/pipeline.sh"
# shellcheck source=case-lib/hijack.sh
source "$SCRIPT_HOME/case-lib/hijack.sh"

# restrict bash version for some bash feature
[[ $(echo -e "$BASH_VERSION\n4.1"|sort -V|head -n 1) == '4.1' ]] || {
    dlogw "Bash version: ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]} should > 4.1"
    exit 2
}

# Add tools to command PATH
# this line equal `! $(echo $PATH|grep "$SCRIPT_HOME/tools")`
if [[ ! $PATH =~ $SCRIPT_HOME/tools ]]; then
    export PATH=$SCRIPT_HOME/tools:$PATH
fi

# setup SOFCARD id
if [ ! "$SOFCARD" ]; then
	# $1=$1 strips whitespaces
	SOFCARD=$(grep -v 'sof-probe' /proc/asound/cards |
		awk '/sof-[a-z]/ && $1 ~ /^[0-9]+$/ { $1=$1; print $1; exit 0;}')
fi

setup_kernel_check_point()
{
    # Make the check point $SOF_TEST_INTERVAL second(s) earlier to avoid log loss.
    # Note this may lead to an error caused by one test appear in the next one.
    KERNEL_CHECKPOINT=$(($(date +%s) - SOF_TEST_INTERVAL))
}

# This function adds a fake error to dmesg (which is always saved by
# journald). It also adds it to kern.log, see why in comment below.
#
# It is surprisingly easy to write a test that always succeeds,
# especially in shell script and it has already happened a number of
# times. Temporarily add this function to a test under development to
# make sure it can actually report failures. Using this function is even
# more critical for testing changes to the test framework and especially
# error handling code.
#
# Sample usage: fake_kern_error "DRIVER ID: FAKE error $0 PID $$ $round"
#               fake_kern_error "asix 3-12.1:1.0 enx000ec668ad2a: Failed to write reg index 0x0000: -11"
fake_kern_error()
{
    local k_msg d boot_secs kern_log_prefix

    k_msg="$1"
    d=$(date '+%b %d %R:%S') # TODO: is this locale dependent?
    boot_secs=$(awk '{ print $1 }' < /proc/uptime)
    kern_log_prefix="$d $(hostname) kernel: [$boot_secs]"

    printf '<3>%s >/dev/kmsg\n' "$k_msg"  | sudo tee -a /dev/kmsg >/dev/null

    # From https://www.kernel.org/doc/Documentation/ABI/testing/dev-kmsg
    # It is not possible to inject to /dev/kmesg with the facility
    # number LOG_KERN (0), to make sure that the origin of the messages
    # can always be reliably determined.
    printf '%s %s >> kern.log\n' "$kern_log_prefix" \
           "$k_msg" | sudo tee -a /var/log/kern.log >/dev/null

}

find_ldc_file()
{
    local ldcFile
    # if user doesn't specify file path of sof-*.ldc, fall back to
    # /etc/sof/sof-PLATFORM.ldc, which is the default path used by CI.
    # and then on the standard location.
    if [ -n "$SOFLDC" ]; then
        ldcFile="$SOFLDC"
    else
        local platf; platf=$(sof-dump-status.py -p) || {
            >&2 dloge "Failed to query platform with sof-dump-status.py"
            return 1
        }
        ldcFile=/etc/sof/sof-"$platf".ldc
        [ -e "$ldcFile" ] ||
            ldcFile=/lib/firmware/intel/sof/sof-"$platf".ldc
    fi

    [[ -e "$ldcFile" ]] || {
        >&2 dloge "LDC file $ldcFile not found, check the SOFLDC environment variable or copy your sof-*.ldc to /etc/sof"
        return 1
    }
    printf '%s' "$ldcFile"
}

SOF_LOG_COLLECT=0
func_lib_start_log_collect()
{
    local is_etrace=${1:-0} ldcFile

    ldcFile=$(find_ldc_file) || return $?

    local logopt="-t"

    if [ -z "$SOFLOGGER" ]; then
        SOFLOGGER=$(command -v sof-logger) || {
            dlogw 'No sof-logger found in PATH'
            return 1
        }
    fi

    test -x "$SOFLOGGER" || {
        dlogw "$SOFLOGGER not found or not executable"
        return 2
    }

    if [ "X$is_etrace" == "X0" ];then
        logfile=$LOG_ROOT/slogger.txt
    else
        logfile=$LOG_ROOT/etrace.txt
        logopt=""
    fi

    if func_hijack_setup_sudo_level ;then
        # shellcheck disable=SC2034 # external script will use it
        SOF_LOG_COLLECT=1
    else
        >&2 dlogw "without sudo permission to run $SOFLOGGER command"
        return 3
    fi

    local loggerCmd="$SOFLOGGER $logopt -l $ldcFile -o $logfile"
    dlogi "Starting $loggerCmd"
    # Cleaned up by func_exit_handler() in hijack.sh
    sudo "$loggerCmd" &
}

# Calling this function is often a mistake because the error message
# from the actual sudo() function in hijack.sh is better: it is
# guaranteed to print the command that needs sudo and give more
# information. func_lib_check_sudo() is useful only when sudo is
# optional and when its warning can be ignored (with '|| true') but in
# the past it has been used to abort the test immediately and lose the
# better error message from sudo().
func_lib_check_sudo()
{
    local cmd="${1:-Unknown command}"
    func_hijack_setup_sudo_level || {
        dlogw "$cmd needs root privilege to run, please use NOPASSWD or cached credentials"
        return 2
    }
}

systemctl_show_pulseaudio()
{
    printf '\n'
    local domain
    for domain in --system --global --user; do
        ( set -x
          systemctl "$domain" list-unit-files --all '*pulse*'
        ) || true
        printf '\n'
    done

    printf 'For %s ONLY:\n' "$(id -un)"
    ( set -x
      systemctl --user list-units --all '*pulse*'
    ) || true
    printf '\n'

    # pgrep ouput is nicer because it hides itself, however pgrep does
    # not show a critical information: the userID which can be not us
    # but 'gdm'!
    # shellcheck disable=SC2009
    ps axu | grep -i pulse
    >&2 printf 'ERROR: %s fails semi-randomly when pulseaudio is running\n' \
        "$(basename "$0")"

    >&2 printf '\nTry: sudo systemctl --global mask pulseaudio.{socket,service} and reboot.
    --global is required for session managers like "gdm"
'
    # We cannot suggest "systemctl --user mask" for a 'gdm' user
    # because we can't 'su' to it and access its DBUS, so we suggest
    # --global to keep it simple. If --global is too strong for you, you
    # can manually create a
    # /var/lib/gdm3/.config/systemd/user/pulseaudio.service -> /dev/null
    # symlink
}

declare -a PULSECMD_LST
declare -a PULSE_PATHS

func_lib_disable_pulseaudio()
{
    [[ "${#PULSECMD_LST[@]}" -ne 0 ]] && return
    # store current pulseaudio command
    readarray -t PULSECMD_LST < <(ps -C pulseaudio -o user,cmd --no-header)
    [[ "${#PULSECMD_LST[@]}" -eq 0 ]] && return
    func_lib_check_sudo 'disabling pulseaudio'
    # get all running pulseaudio paths
    readarray -t PULSE_PATHS < <(ps -C pulseaudio -o cmd --no-header | awk '{print $1}'|sort -u)
    for PA_PATH in "${PULSE_PATHS[@]}"
    do
        # rename pulseaudio before kill it
        if [ -x "$PA_PATH" ]; then
            sudo mv -f "$PA_PATH" "$PA_PATH.bak"
        fi
    done
    sudo pkill -9 pulseaudio
    sleep 1s # wait pulseaudio to be disabled
    if [ ! "$(ps -C pulseaudio --no-header)" ]; then
        dlogi "Pulseaudio disabled"
    else
        # if failed to disable pulseaudio before running test case, fail the test case directly.
        die "Failed to disable pulseaudio"
    fi
}

func_lib_restore_pulseaudio()
{
    [[ "${#PULSECMD_LST[@]}" -eq 0 ]] && return
    func_lib_check_sudo 're-enabling pulseaudio'
    # restore pulseaudio
    for PA_PATH in "${PULSE_PATHS[@]}"
    do
        if [ -x "$PA_PATH.bak" ]; then
            sudo mv -f "$PA_PATH.bak" "$PA_PATH"
        fi
    done
    # start pulseaudio
    local line
    for line in "${PULSECMD_LST[@]}"
    do
        # Both the user and the command are the same $line var :-(
        # shellcheck disable=SC2086
        nohup sudo -u $line >/dev/null &
    done
    # now wait for the pulseaudio restore in the ps process
    timeout=10
    dlogi "Restoring pulseaudio"
    for wait_time in $(seq 1 $timeout)
    do
        sleep 1s
        [ -n "$(ps -C pulseaudio --no-header)" ] && break
        if [ "$wait_time" -eq $timeout ]; then
             dlogi "Time out. Pulseaudio not restored in $timeout seconds"
             return 1
        fi
    done
    dlogi "Restoring pulseaudio takes $wait_time seconds"
    unset PULSECMD_LST
    unset PULSE_PATHS
    declare -ag PULSECMD_LST
    declare -ag PULSE_PATHS
    return 0
}

func_lib_get_random()
{
    # RANDOM: Each time this parameter is referenced, a random integer between 0 and 32767 is generated
    local random_max=$1 random_min=$2 random_scope
    random_scope=$(( random_max - random_min ))
    if [ $# -ge 2 ];then
        echo $(( RANDOM % random_scope + random_min ))
    elif [ $# -eq 1 ];then
        echo $(( RANDOM % random_max ))
    else
        echo $RANDOM
    fi
}

func_lib_lsof_error_dump()
{
    local file="$1" ret
    # lsof exits the same '1' whether the file is missing or not open :-(
    [[ ! -c "$file" ]] && return
    ret=$(lsof "$file") || true
    if [ "$ret" ];then
        dloge "Sound device $file is in use:"
        echo "$ret"
    fi
}

func_lib_get_tplg_path()
{
    local tplg=$1
    if [[ -z "$tplg" ]]; then   # tplg given is empty
        return 1
    elif [[ -f "$TPLG_ROOT/$(basename "$tplg")" ]]; then
        echo "$TPLG_ROOT/$(basename "$tplg")"
    elif [[ -f "$tplg" ]]; then
        realpath "$tplg"
    else
        return 1
    fi

    return 0
}

func_lib_check_pa()
{
    pactl stat || {
        dloge "pactl stat failed"
        return 1
    }
}

# We must not quote SOF_ALSA_OPTS and disable SC2086 below for two reasons:
#
# 1. We want to support multiple parameters in a single variable, in
#    other words we want to support this:
#
#      SOF_ALSA_OPTS="--foo --bar"
#      aplay $SOF_ALSA_OPTS ...
#
# 2. aplay does not ignore empty arguments anyway, in other words this
#    does not work anyway:
#
#      SOF_ALSA_OPTS=""
#      aplay "$SOF_ALSA_OPTS" ...
#
# This is technically incorrect because it means our SOF_ALSA_OPTS
# cannot support whitespace, for instance this would be split in two
# options: --bar="aaaa and bbbb"
#
#      SOF_ALSA_OPTS='--foo --bar="aaaa bbbb"'
#
# To do this "correctly" SOF_ALSA_OPTS etc. should be arrays.
# From https://mywiki.wooledge.org/BashGuide/Arrays "The only safe way
# to represent multiple string elements in Bash is through the use of
# arrays."
#
# However, 1. arrays would complicate the user interface 2. ALSA does not
# seem to need arguments with whitespace or globbing characters.

aplay_opts()
{
    dlogc "aplay $SOF_ALSA_OPTS $SOF_APLAY_OPTS $*"
    # shellcheck disable=SC2086
    aplay $SOF_ALSA_OPTS $SOF_APLAY_OPTS "$@"
}
arecord_opts()
{
    dlogc "arecord $SOF_ALSA_OPTS $SOF_ARECORD_OPTS $*"
    # shellcheck disable=SC2086
    arecord $SOF_ALSA_OPTS $SOF_ARECORD_OPTS "$@"
}

die()
{
    dloge "$@"
    exit 1
}

skip_test()
{
    dlogi "$@"
    # See func_exit_handler()
    exit 2
}

is_sof_used()
{
    grep -q "sof" /proc/asound/cards;
}

# a wrapper to journalctl with required style
journalctl_cmd()
{
   sudo journalctl -k -q --no-pager --utc --output=short-monotonic \
     --no-hostname "$@"
}

disable_kernel_check_point()
{
    KERNEL_CHECKPOINT="disabled"
}

is_zephyr()
{
    # check if jq is installed, will remove this part
    # after all DUTs have jq installed.
    type -p jq || sudo apt install jq -y

    local manifest=/etc/sof/manifest.txt
    test -e "$manifest" || return 1
    jq '.version.firmwareType' "$manifest" | grep "zephyr"
}

logger_disabled()
{
    [[ ${OPT_VAL['s']} -eq 0 ]] || is_zephyr
}

print_module_params()
{
    echo "--------- Printing module parameters ----------"
    grep -H ^ /sys/module/snd_intel_dspcfg/parameters/*

    # for all the *sof* modules
    grep -H ^ /sys/module/*sof*/parameters/*
    echo "----------------------------------------"
}
