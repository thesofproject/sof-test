#!/bin/bash

func_pipeline_export()
{
    # no parameter input the function
    if [ $# -lt 1 ]; then
        dlogi "Topology file name is not specified, unable to run command: ${BASH_SOURCE[-1]}" && exit 1
    fi

    local tplg="$1" opt="" sofcard=${SOFCARD:-0} cmd=""

    # got tplg_file, verify file exist
    tplg_path=`func_lib_get_tplg_path "$tplg"`
    [[ "$?" != "0" ]] && dloge "No available topology for pipeline export" && exit 1
    dlogi "${BASH_SOURCE[-1]} will use topology $tplg_path to run the test case"

    shift
    # create filter option string
    if [ $# -ne 0 ]; then
        opt="-f"
        while [ $# -ne 0 ]
        do
            opt=$opt" $1"
            shift
        done
    fi

    # create block option string
    if [ ${#TPLG_IGNORE_LST[@]} -ne 0 ]; then
        opt=$opt" -b"
        for key in ${!TPLG_IGNORE_LST[@]}
        do
            dlogi "Pipeline list to ignore is specified, will ignore '$key=${TPLG_IGNORE_LST[$key]}' in test case"
            opt=$opt" $key:'${TPLG_IGNORE_LST[$key]}'"
        done
    fi

    cmd=$(echo sof-tplgreader.py $tplg_path $opt -s $sofcard -e)

    OLD_IFS="$IFS" IFS=$'\n'
    dlogi "Run command to get pipeline parameters"
    dlogc "$cmd"
    for line in $(eval $cmd);
    do
        eval $line
    done
    IFS="$OLD_IFS"
    [[ ! "$PIPELINE_COUNT" ]] && dlogw "A problem occured while loading $tplg_path, please check '$cmd' command" && exit 1
    [[ $PIPELINE_COUNT -eq 0 ]] && dlogw "No pipeline found with option: ${opt:3}, unable to run ${BASH_SOURCE[-1]}" && exit 2
    return 0
}

func_pipeline_parse_value()
{
    local idx=$1
    local key=$2
    [[ $idx -ge $PIPELINE_COUNT ]] && echo "" && return
    eval echo "\${PIPELINE_$idx['$key']}"
}
