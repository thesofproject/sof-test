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

OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['r']='round'     OPT_DESC['r']='round count'
OPT_HAS_ARG['r']=1         OPT_VAL['r']=1

OPT_NAME['d']='duration' OPT_DESC['d']='arecord duration in second'
OPT_HAS_ARG['d']=1         OPT_VAL['d']=10

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=3

OPT_NAME['o']='output'   OPT_DESC['o']='output dir'
OPT_HAS_ARG['o']=1         OPT_VAL['o']="$LOG_ROOT/wavs"

OPT_NAME['f']='file'   OPT_DESC['f']='file name prefix'
OPT_HAS_ARG['f']=1         OPT_VAL['f']=''

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

OPT_NAME['F']='fmts'   OPT_DESC['F']='Iterate all supported formats'
OPT_HAS_ARG['F']=0         OPT_VAL['F']=0

OPT_NAME['S']='filter_string'   OPT_DESC['S']="run this case on specified pipelines"
OPT_HAS_ARG['S']=1             OPT_VAL['S']="id:any"

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
round_cnt=${OPT_VAL['r']}
duration=${OPT_VAL['d']}
loop_cnt=${OPT_VAL['l']}
out_dir=${OPT_VAL['o']}
file_prefix=${OPT_VAL['f']}

logger_disabled || func_lib_start_log_collect

setup_kernel_check_point
func_lib_check_sudo
func_pipeline_export "$tplg" "type:capture & ${OPT_VAL['S']}"

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

        if [ ${OPT_VAL['F']} = '1' ]; then
            fmt=$(func_pipeline_parse_value $idx fmts)
        fi

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

                arecord_opts -D$dev -r $rate -c $channel -f $fmt_elem -d $duration $file -v -q
                if [[ $? -ne 0 ]]; then
                    func_lib_lsof_error_dump $snd
                    die "arecord on PCM $dev failed at $i/$loop_cnt."
                fi
            done
        done
    done
done

sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
exit $?
