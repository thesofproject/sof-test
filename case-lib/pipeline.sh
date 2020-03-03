#!/bin/bash

func_pipeline_export()
{
    # no parameter input the function
    if [ $# -lt 1 ]; then
        dlogi "Missing target TPLG file name needed to run ${BASH_SOURCE[-1]}" && exit 1
    fi

    # got tplg_file, verify file exist
    local tplg_str="$1" opt="" sofcard=${SOFCARD:-0} idx=0 tplg_file="" cmd=""
    while [ ${#tplg_str} -gt 0 ]
    do
        # left ',' 1st filed
        f=${tplg_str%%,*}
        # expect left ',' 1st filed
        tplg_str=${tplg_str#*,}
        [ "$f" == "$tplg_str" ] && tplg_str=""
        if [ -f "$TPLG_ROOT/$(basename $f)" ]; then
            f="$TPLG_ROOT/$(basename $f)"   # catch from TPLG_ROOT
        elif [ -f "$f" ];then
            f=$(realpath $f)    # relative path -> absolute path
        else
            dlogw "Couldn't find target TPLG file $f needed to run $0" && exit 1
        fi
        dlogi "${BASH_SOURCE[-1]} using $f as target TPLG to run the test case"
        tplg_file="$tplg_file$f,"
    done
    # remove the right last ','
    tplg_str=${tplg_file/%,/}
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
            dlogi "Catch ignore option from TPLG_IGNORE_LST will ignore '$key=${TPLG_IGNORE_LST[$key]}' for $tplg_str"
            opt=$opt" $key:'${TPLG_IGNORE_LST[$key]}'"
        done
    fi

    cmd=$(echo sof-tplgreader.py $tplg_str $opt -s $sofcard -e)

    OLD_IFS="$IFS" IFS=$'\n'
    dlogi "Run command: '$cmd' to get BASH Array"
    for line in $(eval $cmd);
    do
        eval $line
    done
    IFS="$OLD_IFS"
    [[ ! "$PIPELINE_COUNT" ]] && dlogw "Load $tplg_str meet some problem, please check '$cmd' command" && exit 1
    [[ $PIPELINE_COUNT -eq 0 ]] && dlogw "Missing target PIPELINE for ${opt:3} needed to run ${BASH_SOURCE[-1]}" && exit 2
    return 0
}

func_pipeline_parse_value()
{
    local idx=$1
    local key=$2
    [[ $idx -ge $PIPELINE_COUNT ]] && echo "" && return
    eval echo "\${PIPELINE_$idx['$key']}"
}
