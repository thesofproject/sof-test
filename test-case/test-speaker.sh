#!/bin/bash

##
## Case Name: test-speaker
## Preconditions:
##    Wave file for each channel should be in /usr/share/sounds/alsa,
##    eg, Front_Left.wav, Front_Right.wav, etc.
## Description:
##    Test playback pipelines with speaker-test
## Case step:
##    Iteratively run speaker-test on each playback pipeline
## Expect result:
##    1. speaker-test returns without error.
##    2. Waves are played through corresponding speaker, eg, you should only
##       hear "front left" from the front left speaker.
##

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh


OPT_NAME['t']='tplg'     OPT_DESC['t']="tplg file, default value is env TPLG: $TPLG"
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['l']='loop'     OPT_DESC['l']='option of speaker-test'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=3

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

func_opt_parse_option "$@"
tplg=${OPT_VAL['t']}
logger_disabled || func_lib_start_log_collect

func_pipeline_export "$tplg" "type:playback"
tcnt=${OPT_VAL['l']}
setup_kernel_check_point
for idx in $(seq 0 $((PIPELINE_COUNT - 1)))
do
    channel=$(func_pipeline_parse_value "$idx" channel)
    rate=$(func_pipeline_parse_value "$idx" rate)
    fmt=$(func_pipeline_parse_value "$idx" fmt)
    dev=$(func_pipeline_parse_value "$idx" dev)
    snd=$(func_pipeline_parse_value "$idx" snd)

    dlogc "speaker-test -D $dev -r $rate -c $channel -f $fmt -l $tcnt -t wav -P 8"
    speaker-test -D "$dev" -r "$rate" -c "$channel" -f "$fmt" -l "$tcnt" -t wav -P 8 2>&1 |tee "$LOG_ROOT"/result_"$idx".txt

    resultRet=${PIPESTATUS[0]}

    if grep -nr -E "error|failed" "$LOG_ROOT"/result_"$idx".txt ||
        [[ $resultRet -ne 0  ]]; then
        func_lib_lsof_error_dump "$snd"
        die "speaker test failed"

    fi
done

sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
