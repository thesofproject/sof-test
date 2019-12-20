#!/bin/bash

##
## Case Name: check-playback
## Preconditions:
##    N/A
## Description:
##    run aplay on each pepeline
##    default duration is 10s
##    default loop count is 3
## Case step:
##    1. Parse TPLG file to get pipeline with type of "play" and "both"
##    2. Specify the audio parameters
##    3. Run aplay on each pipeline with parameters
## Expect result:
##    The return value of aplay is 0
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['r']='round'     OPT_DESC_lst['r']='round count'
OPT_PARM_lst['r']=1         OPT_VALUE_lst['r']=1

OPT_OPT_lst['d']='duration' OPT_DESC_lst['d']='aplay duration in second'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=10

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=3

OPT_OPT_lst['f']='file'   OPT_DESC_lst['f']='source file path'
OPT_PARM_lst['f']=1         OPT_VALUE_lst['f']=''

func_opt_add_common_TPLG
func_opt_add_common_sof_logger
func_opt_parse_option $*

tplg=${OPT_VALUE_lst['t']}
round_cnt=${OPT_VALUE_lst['r']}
duration=${OPT_VALUE_lst['d']}
loop_cnt=${OPT_VALUE_lst['l']}
file=${OPT_VALUE_lst['f']}


[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

# checking if source file exists
if [[ -z $file ]]; then
    dlogi "no source file, use /dev/zero as dummy playback source"
    file=/dev/zero
elif [[ ! -f $file ]]; then
    dlogw "$file does not exist, use /dev/zero as dummy playback source"
    file=/dev/zero
else
    dlogi "using $file as playback source"
fi

func_lib_setup_kernel_last_line
func_lib_check_sudo
func_pipeline_export $tplg "type:playback,both"

for round in $(seq 1 $round_cnt)
do
    for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
    do
        channel=$(func_pipeline_parse_value $idx channel)
        rate=$(func_pipeline_parse_value $idx rate)
        fmt=$(func_pipeline_parse_value $idx fmt)
        dev=$(func_pipeline_parse_value $idx dev)
        pcm=$(func_pipeline_parse_value $idx pcm)
        type=$(func_pipeline_parse_value $idx type)

        # clean up dmesg
        sudo dmesg -C
        for i in $(seq 1 $loop_cnt)
        do
            dlogi "Testing: (Round: $round/$round_cnt) (PCM: $pcm [$dev]<$type>) (Loop: $i/$loop_cnt)"
            dlogc "aplay -D$dev -r $rate -c $channel -f $fmt -d $duration $file -vv -q"
            aplay -D$dev -r $rate -c $channel -f $fmt -d $duration $file -vv -q
            if [[ $? -ne 0 ]]; then
                dmesg > $LOG_ROOT/aplay_error_${dev}_$i.txt
                dloge "aplay on PCM $dev failed at $i/$loop_cnt."
                exit 1
            fi
            dmesg > $LOG_ROOT/aplay_${dev}_$i.txt
        done
    done
done

sof-kernel-log-check.sh $KERNEL_LAST_LINE
exit $?
