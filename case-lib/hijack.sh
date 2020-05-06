#!/bin/bash

SUDO_CMD=$(command -v sudo)

trap 'func_exit_handler $?' EXIT
# Overwrite other functions' exit to perform environment cleanup
function func_exit_handler()
{
    local exit_status=${1:-0}

    # when sof logger collect is open
    if [ "X$SOF_LOG_COLLECT" == "X1" ]; then
        # when error occurs, exit and catch etrace log
        [[ $exit_status -eq 1 ]] && {
            func_lib_start_log_collect 1
            sleep 1s
        }
        local loggerBin; loggerBin=$(basename "$SOFLOGGER")
        sudo pkill -9 "$loggerBin" 2>/dev/null
        sleep 1s
    fi
    # when case ends, store kernel log
    if [[ -n "$CASE_KERNEL_START_TIME" ]]; then
        journalctl --flush
        journalctl --dmesg --no-pager --no-hostname -o short-precise --since="$CASE_KERNEL_START_TIME" > "$LOG_ROOT/dmesg.txt"
    else
        journalctl --dmesg --no-pager --no-hostname -o short-precise > "$LOG_ROOT/dmesg.txt"
    fi

    # get ps command result as list
    local -a cmd_lst
    # $$ as current script pid
    # NOTICE: already test with $BASHPID:
    # it can output the same result of $$
    # but the result could not be stored in the array
    readarray -t cmd_lst < <(pgrep -P $$ -a|grep -v "$SCRIPT_NAME")
    # now force kill target process which maybe block the script quit
    if [ ${#cmd_lst[@]} -gt 0 ]; then
        local line
        dlogw "Process(es) started by $SCRIPT_NAME are still active, kill these process(es):"
        for line in "${cmd_lst[@]}"
        do
            dlogw "Catch pid: $line"
            dlogw "Kill cmd:'${line#* }' by kill -9"
            kill -9 "${line%% *}"
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
    if [ "$exit_status" -eq 0 ] && [ $ret -ne 0 ]; then
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

SUDO_LEVEL=""
# overwrite the sudo command, sudo in the script can direct using sudo command
sudo()
{
    func_hijack_setup_sudo_level
    local cmd
    case $SUDO_LEVEL in
        '0')    cmd="$*" # as root
        ;;
        '1')    cmd="$SUDO_CMD env 'PATH=$PATH' $*" # sudo without passwd
        ;;
        '2')    cmd="echo '$SUDO_PASSWD' | $SUDO_CMD -S env 'PATH=$PATH' $*" # sudo need passwd
        ;;
        *)      # without sudo permission
            dlogw "Need root privilege to run $*"
            return 2
    esac
    eval "$cmd"
}

func_hijack_setup_sudo_level()
{
    [[ "$SUDO_LEVEL" ]] && return 0
    # root permission, don't need to check
    [[ $UID -eq 0 ]] && SUDO_LEVEL=0 && return 0
    # now check whether we need sudo passwd using expect
    if expect >/dev/null <<END
spawn $SUDO_CMD ls
expect {
    "password" {
        exit 1
    }
exit 0
}
END
    then
        SUDO_LEVEL=1 && return 0
    fi

    # check for sudo passwd
    if [[ "$SUDO_PASSWD" ]]; then
        [[ $(echo "$SUDO_PASSWD"|$SUDO_CMD -S id -u) -eq 0 ]] && SUDO_LEVEL=2 && return 0
    fi
    return 1
}
