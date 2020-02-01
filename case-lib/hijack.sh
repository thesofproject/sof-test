#!/bin/bash

declare -g SUDO_CMD=$(which sudo)

# Overwrite other functions' exit to perform environment cleanup
function exit()
{
    local exit_status=${1:-0}

    # when sof logger collect is open
    if [ "X$SOF_LOG_COLLECT" == "X1" ];then
        # when have the error exit force catch etrace log
        [[ $exit_status -eq 1 ]] && func_lib_start_log_collect 1 && sleep 1s
        local loggerBin=$(basename $SOFLOGGER)
        sudo pkill -9 $loggerBin 2>/dev/null
        sleep 1s
    fi
    # case quit to store current kernel log
    [[ $DMESG_LOG_START_LINE -ne 0 ]] && \
        tail -n +$DMESG_LOG_START_LINE /var/log/kern.log |cut -f5- -d ' ' > $LOG_ROOT/dmesg.txt

    # get ps command result as list
    OLD_IFS="$IFS" IFS=$'\n'
    local -a cmd_lst
    local line
    # $$ as current script pid
    # NOTICE: already test with $BASHPID:
    # it can output the same result of $$
    # but it couldn't be store the result to the array
    for line in $(ps --ppid $$ -o pid,cmd --no-header|grep -vE "ps|${BASH_SOURCE[-1]}");
    do
        cmd_lst=( "${cmd_lst[@]}" "$line")
    done
    IFS="$OLD_IFS"
    # now force kill target process which maybe block the script quit
    if [ ${#cmd_lst[@]} -gt 0 ]; then
        dlogw "${BASH_SOURCE[-1]} load exit still have those process exist:"
        for line in "${cmd_lst[@]}"
        do
            # remove '^[:space:]' because IFS change to keep the '^[:space:]' in variable
            line=$(echo $line|xargs)
            dlogw "Catch pid: $line"
            dlogw "Kill cmd:'${line#* }' by kill -9"
            kill -9 ${line%% *}
        done
    fi

    # when exit force check the pulseaudio whether disabled
    func_lib_restore_pulseaudio

    # cleanup any aplay / arecord pipelines not closed properly
    pkill aplay
    pkill arecord

    case $exit_status in
        0)
            dlogi "Test Result: PASS!"
        ;;
        1)
            dlogi "Test Result: FAIL!"
        ;;
        2)
            dlogi "Test Result: SKIP!"
        ;;
        *)
            dlogi "Unknown test exit code: $exit_status"
        ;;
    esac

    builtin exit $exit_status
}

# overwrite the sudo command, sudo in the script can direct using sudo command
sudo()
{
    func_hijack_setup_sudo_level
    case $SUDO_LEVEL in
        '0')    # as root
            eval $(echo "$*")
            return $?
        ;;
        '1')    # sudo without passwd
            eval $(echo "$SUDO_CMD env 'PATH=$PATH' $*")
            return $?
        ;;
        '2')    # sudo need passwd
            eval $(echo "echo '$SUDO_PASSWD' | $SUDO_CMD -S env 'PATH=$PATH' $*")
            return $?
        ;;
        *)      # without sudo permission
            dlogw "without permission to run $*"
    esac
    return 2
}

func_hijack_setup_sudo_level()
{
    [[ "$SUDO_LEVEL" ]] && return 0
    # root permission don't need to check
    [[ $UID -eq 0 ]] && SUDO_LEVEL=0 && return 0
    # now check whether we need sudo passwd using expect
    expect >/dev/null <<END
spawn $SUDO_CMD ls
expect {
    "password" {
        exit 1
    }
exit 0
}
END
    [[ $? -eq 0 ]] && SUDO_LEVEL=1 && return 0

    # check for sudo passwd
    if [[ "$SUDO_PASSWD" ]]; then
        local tmp_uid=$(echo "$SUDO_PASSWD"|$SUDO_CMD -S bash -c 'echo $UID')
        [[ $tmp_uid -eq 0 ]] && SUDO_LEVEL=2 && return 0
    fi
    return 1
}
