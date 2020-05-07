#!/bin/bash

# get test-case information
SCRIPT_HOME="$(dirname "$0")"
# get test-case parent folder name
SCRIPT_HOME=$(cd "$SCRIPT_HOME/.." && pwd)
# shellcheck disable=SC2034 # external script can use it
SCRIPT_NAME="$0"  # get test-case script load name
# shellcheck disable=SC2034 # external script can use it
SCRIPT_PRAM="$*"  # get test-case parameter

# Source from the relative path of current folder
# shellcheck disable=SC1091 source=./config.sh
source "$SCRIPT_HOME/case-lib/config.sh"
# shellcheck disable=SC1091 source=./opt.sh
source "$SCRIPT_HOME/case-lib/opt.sh"
# shellcheck disable=SC1091 source=./logging_ctl.sh
source "$SCRIPT_HOME/case-lib/logging_ctl.sh"
# shellcheck disable=SC1091 source=./pipeline.sh
source "$SCRIPT_HOME/case-lib/pipeline.sh"
# shellcheck disable=SC1091 source=./hijack.sh
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
    SOFCARD=$(grep '\]: sof-[a-z]' /proc/asound/cards|awk '{print $1;}')
fi

func_lib_setup_kernel_last_line()
{
    # shellcheck disable=SC2034 # external script will use it
    KERNEL_LAST_LINE=$(journalctl --dmesg --no-pager -n 1 -o short-iso-precise|awk '/kernel/ {print $1;}')
    KERNEL_LAST_LINE=${KERNEL_LAST_LINE:0:-5}
    KERNEL_LAST_LINE=${KERNEL_LAST_LINE/T/ }
}

SOF_LOG_COLLECT=0
func_lib_start_log_collect()
{
    local is_etrace=${1:-0} ldcFile
    ldcFile=/etc/sof/sof-$(sof-dump-status.py -p).ldc || {
        >&2 dlogw "sof-dump-status.py -p to query platform failed"
        return
    }
    local loggerBin="" logfile="" logopt="-t"
    [[ "$SOFLOGGER" ]] && loggerBin=$SOFLOGGER || loggerBin=$(command -v sof-logger)
    if [ "X$is_etrace" == "X0" ];then
        logfile=$LOG_ROOT/slogger.txt
    else
        logfile=$LOG_ROOT/etrace.txt
        logopt=""
    fi
    [[ ! "$loggerBin" ]] && return
    SOFLOGGER=$loggerBin
    if func_hijack_setup_sudo_level ;then
        # shellcheck disable=SC2034 # external script will use it
        SOF_LOG_COLLECT=1
    else
        >&2 dlogw "without sudo permission to run $SOFLOGGER command"
        return
    fi

    sudo "$loggerBin $logopt -l $ldcFile -o $logfile" 2>/dev/null &
}

func_lib_check_sudo()
{
    func_hijack_setup_sudo_level || {
        dlogw "Command needs root privilege to run, please configure SUDO_PASSWD in case-lib/config.sh"
        exit 2
    }
}

declare -a PULSECMD_LST
declare -a PULSE_PATHS

func_lib_disable_pulseaudio()
{
    [[ "${#PULSECMD_LST[@]}" -ne 0 ]] && return
    # store current pulseaudio command
    readarray -t PULSECMD_LST < <(ps -C pulseaudio -o user,cmd --no-header)
    [[ "${#PULSECMD_LST[@]}" -eq 0 ]] && return
    func_lib_check_sudo
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
        echo "Failed to disable pulseaudio"
        exit 1
    fi
}

func_lib_restore_pulseaudio()
{
    [[ "${#PULSECMD_LST[@]}" -eq 0 ]] && return
    func_lib_check_sudo
    # restore pulseaudio
    for PA_PATH in "${PULSE_PATHS[@]}"
    do
        if [ -x "$PA_PATH.bak" ]; then
            sudo mv -f "$PA_PATH.bak" "$PA_PATH"
        fi
    done
    # start pulseaudio
    local cmd="" user="" line=""
    for line in "${PULSECMD_LST[@]}"
    do
        user=${line%% *}
        cmd=${line#* }
        nohup sudo -u "$user" "$cmd" >/dev/null &
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
    [[ ! -c "$file" ]] && return
    ret=$(lsof "$file")
    if [ "$ret" ];then
        dloge "Sound device file is in use:"
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

# force ask buffer data write into file system
sudo sync -f
# catch kern.log last line as current case start line
if [ ! "$DMESG_LOG_START_LINE" ]; then
    DMESG_LOG_START_LINE=$(wc -l /var/log/kern.log|awk '{print $1;}')
fi
