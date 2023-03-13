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


_SOF_TEST_LOCK_FILE=/tmp/sof-test-card"$SOFCARD".lock

# This implements two important features:
#
# 1. Log the start of each test with the current ktime in journalctl.
#
# 2. Tries to detect concurrent sof-test instances. This is performed
#    using (hopefully) atomic filesystem operations and a shared
#    /tmp/sof-test-cardN.lock file that contains the process ID.  It's
#    some kind of a mutex except it's systematically "stolen" to avoid
#    deadlocks after a crash and increase the chances of more tests
#    failing when running concurrently. Past experience before this code
#    showed surprisingly high PASS rates when testing concurrently! (and
#    unvoluntarily).
#
#    `ln` and `mv` are used and hopefully atomic. It's almost sure they
#    are at the filesystem level but it can also depend on the coreutils
#    version according to the latest rumours. Even if they're not, the
#    race window is super small. Even if this code fails to detect
#    concurrency 1% of the time, detecting it 99% of the time is much
#    more than enough to spot reservation problems.
#
start_test()
{
    if is_subtest; then
        return 0
    fi

    test -z "${SOF_TEST_TOP_PID}" || {
        dlogw "SOF_TEST_TOP_PID=${SOF_TEST_TOP_PID} already defined, multiple lib.sh inclusions?"
        return 0
    }

    export SOF_TEST_TOP_PID="$$"
    local prefix; prefix="ktime=$(ktime) sof-test PID=${SOF_TEST_TOP_PID}"
    local ftemp; ftemp=$(mktemp --tmpdir sof-test-XXXXX)
    printf '%s' "${SOF_TEST_TOP_PID}" > "$ftemp"

    # `ln` is supposedly atomic. `mv --no-clobber` is even more likely
    # to be atomic (depending on the coreutils version, see above) but
    # it fails with... an exit status 0!  Useless :-(
    ln "$ftemp" "${_SOF_TEST_LOCK_FILE}" || {
        local lock_pid; lock_pid=$(head -n 1 "${_SOF_TEST_LOCK_FILE}")

        if [ "${SOF_TEST_TOP_PID}" = "$lock_pid" ]; then
            # Internal error
            die "${_SOF_TEST_LOCK_FILE} with ${SOF_TEST_TOP_PID} already exists?!"
        fi

        # Assume this was left-over after a crash, keep running.
        # If another test is really running concurrently then stealing
        # the lock increases the chances of BOTH failing.
        local err_msg
        err_msg=$(printf '%s: %s already taken by PID %s! Stealing it...' \
                  "$prefix" "${_SOF_TEST_LOCK_FILE}" "$lock_pid")
        ln -f "$ftemp" "${_SOF_TEST_LOCK_FILE}"
        dloge "$err_msg"
        logger -p user.err "$err_msg"
    }
    rm "$ftemp"

    local start_msg="$prefix: starting"
    dlogi "$start_msg"
    logger -p user.info "$start_msg"

}

# See high-level description in start_test header above
#
stop_test()
{
    if is_subtest; then
        return 0
    fi

    local ftemp; ftemp=$(mktemp --tmpdir sof-test-XXXXX)
    local prefix; prefix="ktime=$(ktime) sof-test PID=${SOF_TEST_TOP_PID}"
    local err_msg

    # rename(3) is atomic. `mv` hopefully is too.
    mv "${_SOF_TEST_LOCK_FILE}" "$ftemp" || {
        err_msg="$prefix: lock file ${_SOF_TEST_LOCK_FILE} already removed! Concurrent testing?"
        dloge "$err_msg"
        logger -p user.err "$err_msg"
        return 1
    }
    printf '%s' "$SOF_TEST_TOP_PID" > "$ftemp".2

    diff -u "$ftemp".2 "$ftemp" || {
        err_msg="$prefix: unexpected value in ${_SOF_TEST_LOCK_FILE}! Concurrent testing?"
        dloge "$err_msg"
        logger -p user.err "$err_msg"
        return 1
    }

    local end_msg
    end_msg="$prefix: ending"

    dlogi "$end_msg"
    logger -p user.info "$end_msg"

    rm "$ftemp" "$ftemp".2
}


ktime()
{
    # Keep it coarse because of various delays.
    # TODO: does CLOCK_MONOTONIC match dmesg exactly?
    python3 -c \
       'import time; print("%d" % time.clock_gettime(time.CLOCK_MONOTONIC))'
}


# Arguments:
#
#   - poll interval in secs
#   - timeout in secs, rounded up to the next interval
#   - command and arguments
#
poll_wait_for()
{
    test $# -ge 3 ||
        die "poll_wait_for() invoked with $# arguments"

    local ival="$1"; shift
    local maxtime="$1"; shift

    printf "Polling '%s' every ${ival}s for ${maxtime}s\n" "$*"

    local waited=0 attempts=1 pass=true
    while ! "$@"; do
        if [ "$waited" -ge "$maxtime" ]; then
            pass=false
            break;
        fi
        sleep "$ival"
        : $((attempts++));  waited=$((waited+ival))
    done
    local timeinfo="${waited}s and ${attempts} attempts"
    if $pass; then
        printf "Completed '%s' after ${timeinfo}\n" "$*"
    else
        >&2 printf "Command '%s' timed out after ${timeinfo}\n" "$*"
    fi

    $pass
}


storage_checks()
{
    local megas max_sync
    local platf; platf=$(sof-dump-status.py -p)

    case "$platf" in
        # BYT Minnowboards run from SD cards.
        # BSW Cyan has pretty bad eMMC too.
        byt|cht|ehl) megas=4 ; max_sync=25 ;;
        *) megas=100; max_sync=7 ;;
    esac

    ( set -x
      # Thanks to CONT this does not actually timeout; it only returns a
      # non-zero exit status when taking too long.
      time timeout -s CONT "$max_sync" sudo sync || return $?
      # Spend a few seconds to test and show the current write speed
      timeout -s CONT 5 dd if=/dev/zero of=~/HD_TEST_DELETE_ME bs=1M count="$megas" conv=fsync ||
          return $?
      time timeout -s CONT "$max_sync" sudo sync
    ) || return $?

    rm ~/HD_TEST_DELETE_ME
}


setup_kernel_check_point()
{
    # Make the check point $SOF_TEST_INTERVAL second(s) earlier to avoid
    # log loss.  Note this may lead to an error caused by one test
    # appear in the next one, see comments in config.sh.  Add 3 extra
    # second to account for our own, sof-test delays after PASS/FAIL
    # decision: time spent collecting logs etc.
    if [ -z "$KERNEL_CHECKPOINT" ]; then
        KERNEL_CHECKPOINT=$(($(date +%s) - SOF_TEST_INTERVAL - 3))
    else
        # Not the first time we are called so this is a test
        # _iteration_. Add just one extra second in case a test makes
        # the mistake to call this function _after_ checking the logs.
        KERNEL_CHECKPOINT=$(($(date +%s) - 1))
    fi
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

# Prints the .ldc file found on stdout, errors on stderr.
find_ldc_file()
{
    local ldcFile
    # if user doesn't specify file path of sof-*.ldc, fall back to
    # /etc/sof/sof-PLATFORM.ldc, which is the default path used by CI.
    # and then on the standard location.
    if [ -n "$SOFLDC" ]; then
        ldcFile="$SOFLDC"
        >&2 dlogi "SOFLDC=${SOFLDC} overriding default locations"
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
        >&2 dlogi "LDC file $ldcFile not found"
        return 1
    }
    printf '%s' "$ldcFile"
}

func_mtrace_collect()
{
    local clogfile=$LOG_ROOT/mtrace.txt

    if [ -z "$MTRACE" ]; then
        MTRACE=$(command -v mtrace-reader.py) || {
            dlogw 'No mtrace-reader.py found in PATH'
            return 1
        }
    fi

    local mtraceCmd="$MTRACE"
    dlogi "Starting ${mtraceCmd[*]}"
    # Cleaned up by func_exit_handler() in hijack.sh
    # shellcheck disable=SC2024
    sudo "${mtraceCmd[@]}" >& "$clogfile" &
}

func_sof_logger_collect()
{
    logfile=$1
    logopt=$2
    ldcFile=$(find_ldc_file) || return $?

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

    # The logger does not like empty '' arguments and $logopt can be
    # shellcheck disable=SC2206
    local loggerCmd=("$SOFLOGGER" $logopt -l "$ldcFile")
    dlogi "Starting ${loggerCmd[*]}"
    # Cleaned up by func_exit_handler() in hijack.sh
    # shellcheck disable=SC2024
    sudo "${loggerCmd[@]}" > "$logfile" &
}

SOF_LOG_COLLECT=0
# This function starts a logger in the background using '&'
#
# 0. Without any argument is it used to read the DMA trace
# continuously from /sys/kernel/debug/sof/trace.
#
# 1. It is also invoked at the end of a test with an argument other than
# '0' for a one-shot collection of the shared memory 'etrace' in the
# same directory. In that second usage, the caller is expected to sleep
# a little bit while the collection happens in the "pseudo-background".
#
# Note the sof-logger is not able to "stream" logs from the 'etrace'
# ring buffer (nor from any ring buffer), it can only take a snapshot of
# that ring buffer. For the DMA trace, the Linux kernel implements the
# streaming feature. See
# https://github.com/thesofproject/linux/issues/3275 for more info.
#
# Zephyr's cavstool.py implements streaming and is able to read
# continously from the etrace ring buffer.
func_lib_start_log_collect()
{
    local is_etrace=${1:-0} ldcFile
    local log_file log_opt

    if func_hijack_setup_sudo_level ;then
        # shellcheck disable=SC2034 # external script will use it
        SOF_LOG_COLLECT=1
    else
        >&2 dlogw "without sudo permission to run logging command"
        return 3
    fi

    if [ "X$is_etrace" == "X0" ]; then
        if is_ipc4 && is_firmware_file_zephyr; then
            func_mtrace_collect
        else
            log_file=$LOG_ROOT/slogger.txt
            log_opt="-t"
            func_sof_logger_collect "$log_file" "$log_opt"
        fi
    else # once-off etrace collection at end of test
        if is_ipc4; then
            dlogi "No end of test etrace collection for IPC4"
        else
            log_file=$LOG_ROOT/etrace.txt
            log_opt=""
            func_sof_logger_collect "$log_file" "$log_opt"
        fi
    fi

}

check_error_in_file()
{
    local platf; platf=$(sof-dump-status.py -p)

    case "$platf" in
        byt|bdw|bsw)
            # Maybe downgrading this to WARN would be enough, see #799
            #  src/trace/dma-trace.c:654  ERROR dtrace_add_event(): number of dropped logs = 8
            dlogw 'not looking for ERROR on BYT/BDW because of known DMA issues #4333 and others'
            return 0
            ;;
    esac

    test -r "$1" || {
        dloge "file NOT FOUND: '$1'"
        return 1
    }
    # -B 2 shows the header line when the first etrace message is an ERROR
    # -A 1 shows whether the ERROR is last or not.
    if (set -x
        grep -B 2 -A 1 -i --word-regexp -e 'ERR' -e 'ERROR' -e '<err>' "$1"
       ); then
       return 1
    fi
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
    elif [[ -f "$tplg" ]]; then
        realpath "$tplg"
    elif [[ -f "$TPLG_ROOT/$tplg" ]]; then
        echo "$TPLG_ROOT/$tplg"
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
    dlogw 'SKIP test because:'
    dlogw "$@"
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

# Force the exit handler to collect all the logs since boot time instead
# of just the last test iteration.
disable_kernel_check_point()
{
    KERNEL_CHECKPOINT="disabled"
}

# "$@" is optional, usually: --since=@"$epoch_checkpoint"
# shellcheck disable=SC2120
sof_firmware_boot_complete()
{
    journalctl_cmd "$@" | grep -i 'sof.*firmware[[:blank:]]*boot[[:blank:]]*complete'
}

is_zephyr()
{
    local ldcFile
    ldcFile=$(find_ldc_file) || {
        dloge '.ldc file not found, assuming XTOS firmware'
        return 1
    }
    local znum
    znum=$(strings "$ldcFile" | grep -c -i zephyr)
    # As of Nov. 2021, znum ~= 30 for Zephyr and 0 for XTOS
    test "$znum" -gt 10
}

# FIXME: the kernel driver should give us the FW path
# https://github.com/thesofproject/linux/issues/3867
get_firmware_path()
{
    journalctl_cmd -k |
        awk '/sof.*request_firmware/ { sub(/^.*request_firmware/,""); last_loaded_file=$1 } END { print last_loaded_file }'
}

is_firmware_file_zephyr()
{
    local firmware_path znum

    firmware_path=$(get_firmware_path)
    [ -n "$firmware_path" ] ||
        die 'firmware path not found from journalctl, no firmware loaded or debug option disabled?'

    znum=$(strings "/lib/firmware/$firmware_path" | grep -c -i zephyr)
    test "$znum" -gt 10
}

is_ipc4()
{
    local ipc_type
    ipc_file=/sys/module/snd_sof_pci/parameters/ipc_type

    # If /sys/module/snd_sof_pci/parameters/ipc_type does not exist
    # the DUT is running IPC3 mode
    ipc_type=$(cat $ipc_file) || {
        return 1
    }

    # If /sys/module/snd_sof_pci/parameters/ipc_type exists
    # If the value of file ipc_type is:
    # -1: DUT runs IPC3 mode, is_ipc4 return 1(false)
    # 1: DUT runs IPC4 mode, is_ipc4 return 0(true)
    if [ "$ipc_type" -eq 1 ]; then
        return 0
    fi
    return 1
}

logger_disabled()
{
    local ldcFile
    # Some firmware/OS configurations do not support logging.
    ldcFile=$(find_ldc_file) || {
        dlogi '.ldc dictionary file not found, SOF logs collection disabled'
        return 0 # 0 is 'true'
    }

    # Disable logging when available...
    if [ ${OPT_VAL['s']} -eq 0 ]; then
        return 0
    fi

    # ... across all tests at once.
    # In the future we should support SOF_LOGGING=etrace (only), see
    # sof-test#726
    if [ "$SOF_LOGGING" == 'none' ]; then
        dlogi 'SOF logs collection globally disabled by SOF_LOGGING=none'
        return 0
    fi

    if is_ipc4 && ! is_firmware_file_zephyr; then
        dlogi 'IPC4 FW logging only support with SOF Zephyr build'
        dlogi 'SOF logs collection is globally disabled.'
        return 0
    fi

    return 1
}

print_module_params()
{
    echo "--------- Printing module parameters ----------"
    grep -H ^ /sys/module/snd_intel_dspcfg/parameters/* || true

    # for all the *sof* modules
    grep -H ^ /sys/module/*sof*/parameters/* || true
    echo "----------------------------------------"
}

# "$@" is optional, typically: --since=@"$epoch".
# shellcheck disable=SC2120
grep_firmware_info_in_logs()
{
    # dump the version info and ABI info
    # "head -n" makes this compatible with set -e.
    journalctl_cmd "$@" | grep "Firmware info" -A1 | head -n 12
    # For dumping the firmware information when DUT runs IPC4 mode 
    journalctl_cmd "$@" | grep "firmware version" -A1 | head -n 12
    # dump the debug info
    journalctl_cmd "$@" | grep "Firmware debug build" -A3 | head -n 12
}

# check if NTP Synchronized, if so return 0 otherwise return 1
check_ntp_sync()
{
    # Check this device time is NTP Synchronized.
    timedatectl show | grep -q "NTPSynchronized=yes"
}

# alsabat will return -2 for "C.UTF-8" locale
# every case with alsabat should call this at beginning
check_locale_for_alsabat()
{
    if locale | grep -i 'C.utf-8'; then
        die 'Try C.utf8 instead, see https://github.com/alsa-project/alsa-utils/issues/192'
    fi
}

re_enable_ntp_sync()
{
    # disable synchronization first
    sudo timedatectl set-ntp false

    # enable ntp sync. This will trigger initial synchronization to time server
    sudo timedatectl set-ntp true
}

# check-alsabat.sh need to run optimum alsa control settings
# param1: platform name
set_alsa_settings()
{
    # ZEPHYR platform shares same tplg, remove '_ZEPHYR' from platform name
    local PNAME="${1%_ZEPHYR}"
    dlogi "Run alsa setting for $PNAME"
    case $PNAME in
        APL_UP2_NOCODEC | CML_RVP_NOCODEC | JSL_RVP_NOCODEC | TGLU_RVP_NOCODEC | ADLP_RVP_NOCODEC | TGLH_RVP_NOCODEC | MTLP_RVP_NOCODEC)
            # common nocodec alsa settings
            "$SCRIPT_HOME"/alsa_settings/CAVS_NOCODEC.sh
        ;;
        TGLU_RVP_NOCODEC_CI | ADLP_RVP_NOCODEC_CI)
            # common nocodec_ci alsa settings
            "$SCRIPT_HOME"/alsa_settings/CAVS_NOCODEC_CI.sh
        ;;
        *)
            # if script name is same as platform name, default case will handle all
            if [ -f "$SCRIPT_HOME"/alsa_settings/"$PNAME".sh ]; then
                "$SCRIPT_HOME"/alsa_settings/"$PNAME".sh
            else
                dlogw "alsa setting for $PNAME is not available"
            fi
        ;;
    esac
}

reset_sof_volume()
{
    # set all PGA* volume to 0dB
    amixer -Dhw:0 scontrols | sed -e "s/^.*'\(.*\)'.*/\1/" |grep PGA |
    while read -r mixer_name
    do
        amixer -Dhw:0 -- sset "$mixer_name" 0dB
    done
}

start_test
