#!/bin/bash

# using aliases to cover log defines --- more like C log functions
_func_log_cmd()
{
    # the local & remote are different:
    # the local is login
    # the remote is running the commands
    # for example:
    #     remote: ssh xxx@xxx cmd
    #     local: ssh xxx@xxx
    #           $ cmd
    # We can use the system's private environment to know whether this script is
    # run from local or remote
    # Notice: this command only verified on Ubuntu
    local key __LOG_PREFIX=""
    local -A LOG_LIST

    local remote="$LS_COLORS"
    [[ ! "$remote" ]] && __LOG_PREFIX="REMOTE_"

    LOG_LIST['dlogi']="[$__LOG_PREFIX""INFO]"
    LOG_LIST['dloge']="[$__LOG_PREFIX""ERR]"
    LOG_LIST['dlogc']="[$__LOG_PREFIX""COMMAND]"
    LOG_LIST['dlogw']="[$__LOG_PREFIX""WARNING]"

    # open aliases for script, so it can use the dlogx commands instead of
    # writing functions
    shopt -s expand_aliases
    if [ "X1" ]; then
        # PPID: The process ID of the shell's parent.
        # get Current script parent process name
        local ppcmd=$(ps -p $PPID -o cmd --noheader|awk '{print $2;}') ext_message=""
        # confirm this script load by the script, Add the flag for it
        [[ "$(file $ppcmd 2>/dev/null |grep 'shell script')" ]] && ext_message=" Sub-Test:"
        _func_logcmd_add_timestamp()
        {
            echo $(date -u '+%Y-%m-%d %T %Z') $*
        }
        for key in ${!LOG_LIST[@]};
        do
            alias "$key"="_func_logcmd_add_timestamp $ext_message ${LOG_LIST[$key]}"
        done
    else
        _func_empty_function() { return 0; }

        for key in ${!LOG_LIST[@]};
        do
            alias "$key"="_func_empty_function"
        done
    fi
}

# without setting up the LOG_ROOT keyword, now create the log directory for it
_func_log_directory()
{
    [[ "$LOG_ROOT" ]] && return

    local case_name=$(basename ${BASH_SOURCE[-1]})
    local log_dir=$(dirname ${BASH_SOURCE[0]})/../logs/
    local timetag=$(date +%F"-"%T)"-"$RANDOM
    local cur_pwd=$PWD
    case_name=${case_name%.*}
    mkdir -p $log_dir/$case_name/$timetag
    cd $log_dir/$case_name
    # now using the last link for the time tag
    [[ -L last ]] && rm last
    if [[ ! -e last ]]; then
        ln -s $timetag last
        cd last
    else     # if "last" is not the link skip it
        cd $timetag
    fi
    export LOG_ROOT=$PWD
    cd $cur_pwd
}

for _func_ in $(declare -F|grep _func_log_|awk '{print $NF;}')
do
    $_func_
    eval "unset $_func_"
done
unset _func_
