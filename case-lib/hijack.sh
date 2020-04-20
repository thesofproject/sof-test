#!/bin/bash

declare -g SUDO_CMD=$(which sudo)

# Overwrite other functions' exit to perform environment cleanup
function exit()
{
    local exit_status=${1:-0}

    # when sof logger collect is open
    if [ "X$SOF_LOG_COLLECT" == "X1" ]; then
        # when error occurs, exit and catch etrace log
        [[ $exit_status -eq 1 ]] && func_lib_start_log_collect 1 && sleep 1s
        local loggerBin=$(basename $SOFLOGGER)
        sudo pkill -9 $loggerBin 2>/dev/null
        sleep 1s
    fi
    # when case ends, store kernel log
    if [[ -n "$DMESG_LOG_START_LINE" && "$DMESG_LOG_START_LINE" -ne 0 ]]; then
        tail -n +"$DMESG_LOG_START_LINE" /var/log/kern.log |cut -f5- -d ' ' > $LOG_ROOT/dmesg.txt
    else
        cat /var/log/kern.log |cut -f5- -d ' ' > $LOG_ROOT/dmesg.txt
    fi

    # get ps command result as list
    OLD_IFS="$IFS" IFS=$'\n'
    local -a cmd_lst
    local line
    # $$ as current script pid
    # NOTICE: already test with $BASHPID:
    # it can output the same result of $$
    # but the result could not be stored in the array
    for line in $(ps --ppid $$ -o pid,cmd --no-header|grep -vE "ps|${BASH_SOURCE[-1]}");
    do
        cmd_lst=( "${cmd_lst[@]}" "$line")
    done
    IFS="$OLD_IFS"
    # now force kill target process which maybe block the script quit
    if [ ${#cmd_lst[@]} -gt 0 ]; then
        dlogw "Process(es) started by ${BASH_SOURCE[-1]} are still active, kill these process(es):"
        for line in "${cmd_lst[@]}"
        do
            # remove '^[:space:]' because IFS change to keep the '^[:space:]' in variable
            line=$(echo $line|xargs)
            dlogw "Catch pid: $line"
            dlogw "Kill cmd:'${line#* }' by kill -9"
            kill -9 ${line%% *}
        done
    fi

    # check if function already defined.
    # on exit check whether pulseaudio is disabled.
    ret=0
    if [[ $(declare -f func_lib_restore_pulseaudio) ]]; then
        func_lib_restore_pulseaudio
        ret=$?
    fi
    # if failed to restore pulseaudio, even test caes passed, set exit status to ret
    # to make test case failed. this helps to dectect pulseaudio failures.
    if [ $exit_status -eq 0 -a $ret -ne 0 ]; then
        exit_status=$ret
    fi

    case $exit_status in
        0)
            dlogi "Test Result: PASS!"
        ;;
        1)
            dlogi "Test Result: FAIL!"
        ;;
        2)
            dlogi "Test Result: N/A!"
        ;;
        *)
            dlogi "Unknown exit code: $exit_status"
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
            dlogw "Need root privilege to run $*"
    esac
    return 2
}

func_hijack_setup_sudo_level()
{
    [[ "$SUDO_LEVEL" ]] && return 0
    # root permission, don't need to check
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
