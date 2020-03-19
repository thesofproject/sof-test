#!/bin/bash

# Source from the relative path of current folder
source $(dirname ${BASH_SOURCE[0]})/config.sh
source $(dirname ${BASH_SOURCE[0]})/opt.sh
source $(dirname ${BASH_SOURCE[0]})/logging_ctl.sh
source $(dirname ${BASH_SOURCE[0]})/pipeline.sh
source $(dirname ${BASH_SOURCE[0]})/hijack.sh

# Add tools to command PATH
cd $(dirname ${BASH_SOURCE[1]})/../tools
PATH=$PWD:$PATH
cd $OLDPWD

# setup SOFCARD id
if [ ! "$SOFCARD" ]; then
    SOFCARD=$(grep '\]: sof-[a-z]' /proc/asound/cards|awk '{print $1;}')
fi

# Add lock to ensure only one sof-test test-case can run at a time
SOF_LOCK="/tmp/sof-test.lock"
if [ ! -f "$SOF_LOCK" ]; then # lock does not exist
    echo $$ > /tmp/sof-test.lock # write self pid into lock file
elif [ ! "$(alias |grep -i 'Sub-Test')" ]; then # not the sub test-case
    if [ "$(ps -p $(cat $SOF_LOCK) --no-headers)" ]; then # lock exists
        dloge "Lock file $SOF_LOCK already exists: $(ps -p $(cat $SOF_LOCK))"
        # exit 2 # now skip to run the test-case
        exit 3 # mark test-case as incomplete
    else # without other case
        dlogw "Previous test case may exit abnormally"
        echo $$ > /tmp/sof-test.lock # write self pid into lock file
    fi
fi

if [ ! "$DMESG_LOG_START_LINE" ]; then
    declare -g DMESG_LOG_START_LINE=$(wc -l /var/log/kern.log|awk '{print $1;}')
fi

declare -g SOF_LOG_COLLECT=0

func_lib_setup_kernel_last_line()
{
    declare -g KERNEL_LAST_LINE=$(wc -l /var/log/kern.log|awk '{print $1;}')
}

func_lib_start_log_collect()
{
    local is_etrace=${1:-0}
    local ldcFile=/etc/sof/sof-$(sof-dump-status.py -p).ldc
    local loggerBin="" logfile="" logopt="-t"
    [[ "$SOFLOGGER" ]] && loggerBin=$SOFLOGGER || loggerBin=$(which sof-logger)
    if [ "X$is_etrace" == "X0" ];then
        logfile=$LOG_ROOT/slogger.txt
    else
        logfile=$LOG_ROOT/etrace.txt
        logopt=""
    fi
    [[ ! "$loggerBin" ]] && return
    SOFLOGGER=$loggerBin
    func_hijack_setup_sudo_level
    [[ $? -eq 0 ]] && SOF_LOG_COLLECT=1

    sudo $loggerBin $logopt -l $ldcFile -o $logfile 2>/dev/null &
}

func_lib_check_sudo()
{
    func_hijack_setup_sudo_level
    [[ $? -ne 0 ]] && \
        dlogw "Command needs root privilege to run, please configure SUDO_PASSWD in case-lib/config.sh" && \
        exit 2
}

declare -ag PULSECMD_LST

func_lib_disable_pulseaudio()
{
    [[ "${#PULSECMD_LST[@]}" -ne 0 ]] && return
    # store current pulseaudio command
    OLD_IFS="$IFS" IFS=$'\n'
    PULSECMD_LST=( $(ps -C pulseaudio -o user,cmd --no-header) )
    IFS="$OLD_IFS"
    [[ "${#PULSECMD_LST[@]}" -eq 0 ]] && return
    func_lib_check_sudo
    [[ ! -f $PULSEAUDIO_CONFIG.bak ]] && sudo cp $PULSEAUDIO_CONFIG $PULSEAUDIO_CONFIG.bak -f
    # because hijack the sudo command
    if [ "$(grep 'autospawn' $PULSEAUDIO_CONFIG)" ]; then
        sudo "sed -i '/autospawn/cautospawn = no' $PULSEAUDIO_CONFIG"
    else
        sudo "bash -c 'echo \"autospawn = no\" >> $PULSEAUDIO_CONFIG'"
    fi
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
    [[ -f $PULSEAUDIO_CONFIG.bak ]] && sudo mv -f $PULSEAUDIO_CONFIG.bak $PULSEAUDIO_CONFIG
    local cmd="" user="" line=""
    for line in "${PULSECMD_LST[@]}"
    do
        user=${line%% *}
        cmd=${line#* }
        nohup sudo -u $user $cmd >/dev/null &
    done
    # now wait for the pulseaudio restore in the ps process
    timeout=10
    dlogi "Restoring pulseaudio"
    for wait_time in $(seq 1 $timeout)
    do
        sleep 1s
        [ -n "$(ps -C pulseaudio --no-header)" ] && break
        if [ $wait_time -eq $timeout ]; then
             dlogi "Time out. Pulseaudio not restored in $timeout seconds"
             return 1
        fi
    done
    dlogi "Restoring pulseaudio takes $wait_time seconds"
    unset PULSECMD_LST
    declare -ag PULSECMD_LST
    return 0
}

func_lib_get_random()
{
    # RANDOM: Each time this parameter is referenced, a random integer between 0 and 32767 is generated
    local random_max random_min random_scope
    if [ $# -ge 2 ];then
        random_max=$2
        random_min=$1
        random_scope=$(expr $random_max - $random_min)
        expr $RANDOM % $random_scope + $random_min
    elif [ $# -eq 1 ];then
        random_max=$1
        expr $RANDOM % $random_max
    else
        echo $RANDOM
    fi
}

func_lib_lsof_error_dump()
{
    local file=$1
    [[ ! -f $file ]] && return
    local ret=$(lsof $file)
    if [ "$ret" ];then
        dloge "Sound device file is in use:"
        echo "$ret"
    fi
}
