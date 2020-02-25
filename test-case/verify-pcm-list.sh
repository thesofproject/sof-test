#!/bin/bash

##
## Case Name: verify PCM list with tplg file
## Preconditions:
##    driver already to load
## Description:
##    using /proc/asound/pcm to compare with tplg content
## Case step:
##    1. load tplg file to get pipeline list string
##    2. load /proc/asound/pcm to get pcm list string
##    3. compare string list
## Expect result:
##    pipeline list is same as pcm list
##

# source from the relative path of current folder
source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

func_opt_parse_option $*
tplg=${OPT_VALUE_lst['t']}

[[ ! "$tplg" ]] && dlogw "Missing tplg file for this case" && exit 1

# hijack DMESG_LOG_START_LINE which refer dump kernel log in exit function
DMESG_LOG_START_LINE=$(sof-get-kernel-line.sh|tail -n 1 |awk '{print $1;}')

# check TPLG by the loop
# TODO: current miss multiple tplg behaivor
# so this case logic just for 1 tplg process
while [ ${#tplg} -gt 0 ]
do
    # go through each TPLG file and check the PCM list
    # left ',' 1st filed
    tplg_file=${tplg%%,*}
    # expect left ',' 1st filed
    tplg=${tplg#*,}
    [ "$tplg_file" == "$tplg" ] && tplg=""
    if [ -f "$TPLG_ROOT/$(basename $tplg_file)" ]; then
        tplg_file="$TPLG_ROOT/$(basename $tplg_file)"   # catch from TPLG_ROOT
    elif [ -f "$tplg_file" ];then
        tplg_file=$(realpath $tplg_file)    # relative path -> absolute path
    else
        dloge "Couldn't find target TPLG file $tplg_file needed to run ${BASH_SOURCE[0]}" && exit 1
    fi

    tplg_str="$(sof-tplgreader.py $tplg_file -d id pcm type -o)"
    pcm_str="$(sof-dump-status.py -i ${SOFCARD:-0})"

    dlogi "CMD: 'sof-tplgreader.py $tplg_file -d id pcm type -o' to get tplg list string:"
    echo "$tplg_str"
    dlogi "CMD: 'sof-dump-status.py -i ${SOFCARD:-0}' to get pcm list string:"
    echo "$pcm_str"

    if [[ "$tplg_str" != "$pcm_str" ]]; then
        dloge "TPLG mismatch with PCM"
        dlogi "Dump aplay -l"
        aplay -l
        dlogi "Dump arecord -l"
        arecord -l
        exit 1
    fi

    # TODO: Miss multiple TPLG mapping pcm logic
    break
done

exit 0
