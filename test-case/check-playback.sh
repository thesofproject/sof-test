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
##    1. Parse TPLG file to get pipeline with type of "play"
##    2. Specify the audio parameters
##    3. Run aplay on each pipeline with parameters
## Expect result:
##    The return value of aplay is 0
##

set -e

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['r']='round'     OPT_DESC['r']='round count'
OPT_HAS_ARG['r']=1         OPT_VAL['r']=1

OPT_NAME['d']='duration' OPT_DESC['d']='aplay duration in second'
OPT_HAS_ARG['d']=1         OPT_VAL['d']=10

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=3

OPT_NAME['f']='file'   OPT_DESC['f']='source file path'
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
file=${OPT_VAL['f']}


logger_disabled || func_lib_start_log_collect

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

setup_kernel_check_point
func_lib_check_sudo
func_pipeline_export "$tplg" "type:playback & ${OPT_VAL['S']}"

for round in $(seq 1 $round_cnt)
do
    for idx in $(seq 0 $((PIPELINE_COUNT - 1)))
    do
        channel=$(func_pipeline_parse_value "$idx" channel)
        rate=$(func_pipeline_parse_value "$idx" rate)
        fmts=$(func_pipeline_parse_value "$idx" fmt)
        dev=$(func_pipeline_parse_value "$idx" dev)
        pcm=$(func_pipeline_parse_value "$idx" pcm)
        type=$(func_pipeline_parse_value "$idx" type)
        snd=$(func_pipeline_parse_value "$idx" snd)

        if [ ${OPT_VAL['F']} = '1' ]; then
            fmts=$(func_pipeline_parse_value "$idx" fmts)
        fi

        for fmt_elem in $fmts
        do
            for i in $(seq 1 $loop_cnt)
            do
                dlogi "===== Testing: (Round: $round/$round_cnt) (PCM: $pcm [$dev]<$type>) (Loop: $i/$loop_cnt) ====="
                aplay_opts -D"$dev" -r "$rate" -c "$channel" -f "$fmt_elem" \
                      -d "$duration" "$file" -v -q || {
                    func_lib_lsof_error_dump "$snd"
                    die "aplay on PCM $dev failed at $i/$loop_cnt."
                }
            done
        done
    done
done

sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
