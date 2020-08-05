#!/bin/bash

##
## Case Name: check_echo_reference
## Preconditions:
##    N/A
## Description:
##    using alsabat to check the echo reference
## Case step:
##    1. play sine wave on echo reference playback pipeline
##    2. capture the data through the internel loopback
##    3. use alsabat to analyze the recorded data
## Expect result:
##    no errors and the captured data should match with the orignal one
##

# remove the existing alsabat wav files
rm -f /tmp/bat.wav.*

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"
OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1
OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=1
OPT_OPT_lst['n']='frames'     OPT_DESC_lst['n']='test frames'
OPT_PARM_lst['n']=1             OPT_VALUE_lst['n']=240000
OPT_OPT_lst['f']='frequency'    OPT_DESC_lst['f']='target frequency'
OPT_PARM_lst['f']=1             OPT_VALUE_lst['f']=997

func_opt_parse_option "$@"

tplg=${OPT_VALUE_lst['t']}
loop_cnt=${OPT_VALUE_lst['l']}
frames=${OPT_VALUE_lst['n']}
frequency=${OPT_VALUE_lst['f']}

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

func_pipeline_export $tplg "echo:any"
func_lib_setup_kernel_last_line

function __upload_wav_file
{
    # upload the alsabat wav file
    for file in /tmp/bat.wav.*
    do
        size=$(ls -l "$file" | awk '{print $5}')
        if [[ $size -gt 0 ]]; then
            cp "$file" "$LOG_ROOT/"
        fi
    done
}

if [ "$PIPELINE_COUNT" != "2" ]; then
    die "Only detect $PIPELINE_COUNT pipeline(s) from topology, but two are needed"
fi

for idx in $(seq 0 $(("$PIPELINE_COUNT" - 1)))
do
    type=$(func_pipeline_parse_value "$idx" type)
    if [ "$type" == "playback" ]; then
        channel=$(func_pipeline_parse_value "$idx" ch_max)
        rate=$(func_pipeline_parse_value "$idx" rate)
        pb_dev=$(func_pipeline_parse_value "$idx" dev)
    else
        cp_dev=$(func_pipeline_parse_value "$idx" dev)
        fmt=$(func_pipeline_parse_value "$idx" fmt)
        fmts=$(func_pipeline_parse_value "$idx" fmts)
    fi
done

for i in $(seq 1 $loop_cnt)
do
    for fmt in $fmts
    do
    printf "Testing: iteration %d of %d with %s format\n" "$i" "$loop_cnt" "$fmt"
        # S24_LE format is not supported
        if [ "$fmt" == "S24_LE" ]; then
            continue
        fi
        # run echo reference test
        dlogc "alsabat -P $pb_dev --standalone -c $channel -f $fmt -r $rate -n $frames -F $frequency"
        alsabat -P "$pb_dev" --standalone -c "$channel" -f "$fmt" -r "$rate" -n "$frames" -F "$frequency" &
        # playback may have low latency, add 0.5 second delay to aviod recording zero at beginning.
        sleep 1
        dlogc "alsabat -C $cp_dev -c $channel -f $fmt -r $rate -F $frequency"
        alsabat -C "$cp_dev" -c "$channel" -f "$fmt" -r "$rate" -F "$frequency"

        # upload failed wav file
        if [[ "$?" != "0" ]]; then
            __upload_wav_file
        exit 1
        fi
    sleep 2 # 2 seconds interval for next run
    done
done

sof-kernel-log-check.sh "$KERNEL_LAST_LINE"
