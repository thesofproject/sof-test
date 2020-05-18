#!/bin/bash

func_pipeline_export()
{
    # no parameter input the function
    if [ $# -lt 1 ]; then
        dlogi "Topology file name is not specified, unable to run command: $SCRIPT_NAME"
        exit 1
    fi
    # got tplg_file, verify file exist
    tplg_path=$(func_lib_get_tplg_path "$1") || {
        dloge "No available topology for pipeline export"
        exit 1
    }
    dlogi "$SCRIPT_NAME will use topology $tplg_path to run the test case"

    # create block option string
    local ignore=""
    if [ ${#TPLG_IGNORE_LST[@]} -ne 0 ]; then
        for key in "${!TPLG_IGNORE_LST[@]}"
        do
            dlogi "Pipeline list to ignore is specified, will ignore '$key=${TPLG_IGNORE_LST[$key]}' in test case"
            ignore=$ignore" $key:${TPLG_IGNORE_LST[$key]}"
        done
    fi

    local opt=""
    # acquire filter option
    [[ "$2" ]] && opt="-f '$2'"
    [[ "$ignore" ]] && opt="$opt -b '$ignore'"
    [[ "$SOFCARD" ]] && opt="$opt -s $SOFCARD"

    local -a pipeline_lst
    local cmd="sof-tplgreader.py $tplg_path $opt -e" line=""
    dlogi "Run command to get pipeline parameters"
    dlogc "$cmd"
    readarray -t pipeline_lst < <(eval "$cmd")
    for line in "${pipeline_lst[@]}"
    do
        eval "$line"
    done
    [[ ! "$PIPELINE_COUNT" ]] && dlogw "Failed to parse $tplg_path, please check topology parsing command" && exit 1
    [[ $PIPELINE_COUNT -eq 0 ]] && dlogw "No pipeline found with option: $opt, unable to run $SCRIPT_NAME" && exit 2
    return 0
}

func_pipeline_parse_value()
{
    local idx=$1
    local key=$2
    [[ $idx -ge $PIPELINE_COUNT ]] && echo "" && return
    local array_key='PIPELINE_'"$idx"'['"$key"']'
    eval echo "\${$array_key}" # dynmaic echo the target value of the PIPELINE
}
