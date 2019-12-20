#!/bin/bash

##
## Case Name: verify PCM list with tplg file
## Preconditions:
##    driver already to load
## Description:
##    using /proc/asound/pcm to compare with tplg content
## Case step:
##    1. load tplg file to get pipeline list
##    2. load /proc/asound/pcm to get pcm list
##    3. compare count
##    4. compare type, pcm keyword between pipeline & pcm with same id
## Expect result:
##    pipeline list is same as pcm list
##

# source from the relative path of current folder
source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

func_opt_add_common_TPLG
func_opt_parse_option $*
tplg=${OPT_VALUE_lst['t']}

# because here is verify tplg file load result by driver
# so don't need block list option
unset TPLG_BLOCK_LST

func_asound_pcm_export()
{
    local sofcard=${SOFCARD:-0}

    cmd=$(echo sof-dump-status.py -i $sofcard)
    OLD_IFS="$IFS" IFS=$'\n'
    dlogi "Run command: '$cmd' to get BASH Array"
    for line in $(eval $cmd);
    do
        eval $line
    done
    IFS="$OLD_IFS"
    [[ ! "$ASOUND_PCM_COUNT" ]] && dloge "run $cmd without any pcm detected ,please check with /proc/asound/pcm information" && exit 1
    [[ $ASOUND_PCM_COUNT -eq 0 ]] && dloge "Missing target PCM list" && exit 1
    return 0
}

func_asound_pcm_parse_value()
{
    eval echo "\${ASOUND_PCM_$1['$2']}"
}

func_error_process()
{
    local tplg_file="$1" sofcard=${SOFCARD:-0}
    shift
    dloge $*
    dlogi "Dump PCM List"
    cat /proc/asound/pcm
    dlogi "Dump TPLG List"
    sof-tplgreader.py $tplg_file -s $sofcard
    dlogi "Dump aplay -l"
    aplay -l
    dlogi "Dump arecord -l"
    arecord -l
    exit 1
}

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
    if [ -f "$tplg_file" ]; then
        tplg_file="$f"
    elif [ -f "$TPLG_ROOT/$tplg_file" ]; then
        tplg_file="$TPLG_ROOT/$tplg_file"
    else
        dloge "Couldn't find target TPLG file $tplg_file needed to run ${BASH_SOURCE[0]}" && exit 1
    fi

    func_pipeline_export $tplg_file
    func_asound_pcm_export

    [[ $PIPELINE_COUNT -ne $ASOUND_PCM_COUNT ]] && \
        dloge "pipeline count:$PIPELINE_COUNT in tplg file mismatch with system asound count:$ASOUND_PCM_COUNT"

    for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
    do
        # vierfy the pcm list for keyword: type, id, pcm
        pid=$(func_pipeline_parse_value $idx id)
        ptype=$(func_pipeline_parse_value $idx type)
        ppcm=$(func_pipeline_parse_value $idx pcm)
        aid=$(func_asound_pcm_parse_value $pid id)
        atype=$(func_asound_pcm_parse_value $pid type)
        apcm=$(func_asound_pcm_parse_value $pid pcm)
        dlogi "Comparing $ptype device $pid: $ppcm"
        [[ "$pid" != "$aid" ]] && func_error_process $tplg_file "id $pid mismatch, tplg id: $pid, asound type: $aid" && exit 1
        [[ "$ptype" != "$atype" ]] && func_error_process $tplg_file "id $pid mismatch, tplg type: $ptype, asound type: $atype" && exit 1
        [[ "$ppcm" != "$apcm" ]] && func_error_process $tplg_file "id $pid mismatch, tplg pcm: $ppcm, asound pcm: $apcm" && exit 1
    done

    # TODO: Miss multiple TPLG mapping pcm logic
    break
done

exit 0
