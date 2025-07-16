#!/bin/bash

set -e

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

OPT_NAME['t']='tplg'         OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1             OPT_VAL['t']="$TPLG"
OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1
OPT_NAME['l']='loop'         OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1             OPT_VAL['l']=1
OPT_NAME['n']='frames'       OPT_DESC['n']='test frames'
OPT_HAS_ARG['n']=1             OPT_VAL['n']=240000
OPT_NAME['f']='frequency'    OPT_DESC['f']='target frequency'
OPT_HAS_ARG['f']=1             OPT_VAL['f']=997

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
loop_cnt=${OPT_VAL['l']}
frames=${OPT_VAL['n']}
frequency=${OPT_VAL['f']}

start_test
logger_disabled || func_lib_start_log_collect

func_pipeline_export "$tplg" "echo:any"
setup_kernel_check_point

if [ "$PIPELINE_COUNT" != "2" ]; then
    die "Only detect $PIPELINE_COUNT pipeline(s) from topology, but two are needed"
fi

setup_alsa

for idx in $(seq 0 $((PIPELINE_COUNT - 1)))
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
            dlogi "S24_LE is not supported, skip to test this format"
            continue
        fi
        # run echo reference test
        dlogc "alsabat -P $pb_dev --standalone -c $channel -f $fmt -r $rate -n $frames -F $frequency"
        timeout -k 2 6 alsabat -P "$pb_dev" --standalone -c "$channel" -f "$fmt" -r "$rate" -n "$frames" \
		-F "$frequency" & alsabatPID=$!
        # playback may have low latency, add 1 second delay to aviod recording zero at beginning.
        sleep 1
        dlogc "alsabat -C $cp_dev -c $channel -f $fmt -r $rate -F $frequency"
        alsabat -C "$cp_dev" -c "$channel" -f "$fmt" -r "$rate" -F "$frequency" || {
            # upload failed wav files
            find /tmp -maxdepth 1 -type f -name "bat.wav.*" -size +0 -exec cp {} "$LOG_ROOT/" \;
            die "alsabat test failed on pcm: $cp_dev"
        }

        wait $alsabatPID || die "Failed to stop alsabat playback"

    sleep 2 # 2 seconds interval for next run
    done
done

sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
