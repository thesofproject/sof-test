#!/bin/bash

##
## Case Name: check-capture
## Preconditions:
##    N/A
## Description:
##    run arecord on each pepeline
##    default duration is 10s
##    default loop count is 3
## Case step:
##    1. Parse TPLG file to get pipeline with type of "record"
##    2. Specify the audio parameters
##    3. Run arecord on each pipeline with parameters
## Expect result:
##    The return value of arecord is 0
##

set -e

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['r']='round'     OPT_DESC_lst['r']='round count'
OPT_PARM_lst['r']=1         OPT_VALUE_lst['r']=1

OPT_OPT_lst['d']='duration' OPT_DESC_lst['d']='arecord duration in second'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=10

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=3

OPT_OPT_lst['o']='output'   OPT_DESC_lst['o']='output dir'
OPT_PARM_lst['o']=1         OPT_VALUE_lst['o']="$LOG_ROOT/wavs"

OPT_OPT_lst['f']='file'   OPT_DESC_lst['f']='file name prefix'
OPT_PARM_lst['f']=1         OPT_VALUE_lst['f']=''

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

OPT_OPT_lst['F']='fmts'   OPT_DESC_lst['F']='Iterate all supported formats'
OPT_PARM_lst['F']=0         OPT_VALUE_lst['F']=0

OPT_OPT_lst['S']='filter_string'   OPT_DESC_lst['S']="run this case on specified pipelines"
OPT_PARM_lst['S']=1             OPT_VALUE_lst['S']="id:any"

func_opt_parse_option "$@"

tplg=${OPT_VALUE_lst['t']}
round_cnt=${OPT_VALUE_lst['r']}
duration=${OPT_VALUE_lst['d']}
loop_cnt=${OPT_VALUE_lst['l']}
out_dir=${OPT_VALUE_lst['o']}
file_prefix=${OPT_VALUE_lst['f']}

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

func_lib_setup_kernel_last_timestamp
func_lib_check_sudo
func_pipeline_export $tplg "type:capture & ${OPT_VALUE_lst['S']}"

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
        snd=$(func_pipeline_parse_value $idx snd)

        if [ ${OPT_VALUE_lst['F']} = '1' ]; then
            fmt=$(func_pipeline_parse_value $idx fmts)
        fi
        # clean up dmesg
        sudo dmesg -C
        for fmt_elem in $(echo $fmt)
        do
            for i in $(seq 1 $loop_cnt)
            do
                dlogi "===== Testing: (Round: $round/$round_cnt) (PCM: $pcm [$dev]<$type>) (Loop: $i/$loop_cnt) ====="
                # get the output file
                if [[ -z $file_prefix ]]; then
                    dlogi "no file prefix, use /dev/null as dummy capture output"
                    file=/dev/null
                else
                    mkdir -p $out_dir
                    file=$out_dir/${file_prefix}_${dev}_${i}.wav
                    dlogi "using $file as capture output"
                fi

                dlogc "arecord -D$dev -r $rate -c $channel -f $fmt_elem -d $duration $file -v -q"
                arecord -D$dev -r $rate -c $channel -f $fmt_elem -d $duration $file -v -q
                if [[ $? -ne 0 ]]; then
                    func_lib_lsof_error_dump $snd
                    die "arecord on PCM $dev failed at $i/$loop_cnt."
                fi
            done
        done
    done
done

sof-kernel-log-check.sh $KERNEL_LAST_TIMESTAMP
exit $?
