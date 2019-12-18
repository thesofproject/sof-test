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
if [ ! "$SOFCARD" ];then
    SOFCARD=$(grep '\]: sof-[a-z]' /proc/asound/cards|awk '{print $1;}')
fi

if [ ! "$DMESG_LOG_START_LINE" ];then
    declare -g DMESG_LOG_START_LINE=$(wc -l /var/log/kern.log|awk '{print $1;}')
fi
declare -g SOF_LOG_COLLECT=0
# To record output to STRESS_OUTPUT_LOG
declare -g STRESS_OUTPUT_LOG
# To record script status to STRESS_STATUS_LOG
declare -g STRESS_STATUS_LOG

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
        dlogw "Next command needs root permission to run. If you haven't done so, please configure SUDO_PASSWD in case-lib/config.sh file" && \
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
    sudo "sed -i '/autospawn/cautospawn = no' $PULSEAUDIO_CONFIG"
    sudo pkill -9 pulseaudio
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
        sudo -u $user $cmd >/dev/null 2>&1 &
    done
    unset PULSECMD_LST
    declare -ag PULSECMD_LST
}

func_lib_trigger_stress()
{
    export LOG_ROOT=$LOG_ROOT
    STRESS_OUTPUT_LOG="$LOG_ROOT/stress.txt"
    STRESS_STATUS_LOG="$LOG_ROOT/status.txt"
    [[ -f $STRESS_OUTPUT_LOG ]] && return

    touch $STRESS_OUTPUT_LOG
    touch $STRESS_STATUS_LOG
    if [ "$SSH_CLIENT" ];then
        # convert itself to nohup without ssh lost connect when case trigger by ssh connect
        if [ $PPID -ne 1 ];then
            dlogi "redirect the output please check for $STRESS_OUTPUT_LOG"
            nohup $(cat $LOG_ROOT/cmd-orig.txt) > $STRESS_OUTPUT_LOG &
            # delay for nohup command apply
            sleep 1s
            # now output current process with tail command
            clear
            tail -f $STRESS_OUTPUT_LOG
            builtin exit 0
        fi
    fi
}
