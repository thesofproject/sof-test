#!/bin/bash

##
## Case Name: check-performance
## Preconditions:
##    N/A
## Description:
##    Run aplay and arecord to playback and capture
##    pipelines of the benchmark topology:
##        sof-hda-benchmark-generic-PLATFORM.tplg
## Case step:
##    1. Parse TPLG file to get pipeline with type of playback
##       and capture (exclude HDMI pipeline)
##    2. Specify the audio parameters
##    3. Run aplay and arecord on each pipeline with audio parameters
## Expect result:
##    The return value of aplay/arecord is 0
##    Performance statistics are printed
##

set -e

# It is pointless to perf component in HDMI pipeline, so filter out HDMI pipelines
# shellcheck disable=SC2034
NO_HDMI_MODE=true

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['d']='duration' OPT_DESC['d']='aplay/arecord duration in second'
OPT_HAS_ARG['d']=1         OPT_VAL['d']=30

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
duration=${OPT_VAL['d']}

logger_disabled || func_lib_start_log_collect

setup_kernel_check_point
func_lib_check_sudo
func_pipeline_export "$tplg" "type:any"

for idx in $(seq 0 $((PIPELINE_COUNT - 1)))
do
        channel=$(func_pipeline_parse_value "$idx" channel)
        rate=$(func_pipeline_parse_value "$idx" rate)
        dev=$(func_pipeline_parse_value "$idx" dev)
        pcm=$(func_pipeline_parse_value "$idx" pcm)
        type=$(func_pipeline_parse_value "$idx" type)

        # Currently, copier will convert bit depth to S32_LE despite what bit depth
        # is used in aplay, so make S32_LE as base bit depth for performance analysis.
        fmt=S32_LE

        dlogi "Running (PCM: $pcm [$dev]<$type>) in background"
        if [ "$type" == "playback" ]; then
            aplay_opts -D "$dev" -c "$channel" -r "$rate" -f "$fmt" -d "$duration" /dev/zero -q &
        else
            arecord_opts -D "$dev" -c "$channel" -r "$rate" -f "$fmt" -d "$duration" /dev/null -q &
        fi
done

dlogi "Waiting for aplay/arecord process to exit"
sleep $((duration + 2))

# Enable performance analysis
# shellcheck disable=SC2034
DO_PERF_ANALYSIS=1
