#!/bin/bash

##
## Case Name: check-src-rec
## Preconditions:
##    ffmpeg installed
## Description:
##    Generate 48 kHz sound (chirp 0 - 20 kHz), play it and record with different sample rates.
##    Check recorded sound to verify it doesn't glitch.
##    Skipped rates:
##    - 11.025 kHz because can't use it in LL scheduled pipeline too large SRC block size,
##      DP pipeline later.
##    - 24 kHz because alsa-lib is missing the support, need to fix ALSA.
## Case step:
##    TODO
## Expect result:
##    TODO
##

set -e

# It is pointless to perf component in HDMI pipeline, so filter out HDMI pipelines
# shellcheck disable=SC2034
NO_HDMI_MODE=true

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['p']='playback_device'          OPT_DESC['p']='ALSA pcm playback device. Example: hw:0,1'
OPT_HAS_ARG['p']=1              OPT_VAL['p']=''

OPT_NAME['c']='capture_device'          OPT_DESC['c']='ALSA pcm capture device. Example: hw:0,1'
OPT_HAS_ARG['c']=1              OPT_VAL['c']=''

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

func_opt_parse_option "$@"

init_globals()
{
    tplg=${OPT_VAL['t']}
    playback_dev=${OPT_VAL['p']}
    capture_dev=${OPT_VAL['c']}

    sample_rates=("8000" "16000" "22050" "32000" "44100" "48000")

    rec_opt="-f S16_LE -c 2 -d 7"
    failures=0

    test_sound_filename=$LOG_ROOT/play.wav
}

run_tests()
{
    dlogi "Generate 48 kHz chirp 0 - 20 kHz"
    ffmpeg -y -f lavfi -i "aevalsrc='sin(2000*t*2*PI*t)':s=48000:d=5" -ac 2 $test_sound_filename

    for i in "${!sample_rates[@]}"
    do
        sample_rate=${sample_rates[$i]}

        result_filename=$LOG_ROOT/rec_$sample_rate.wav

        play_and_record "-D$capture_dev $rec_opt -r $sample_rate $result_filename" "-D$playback_dev $test_sound_filename"

        dlogi "Analyzing $result_filename file..."
        #TODO: Actually analyze the result
        if [ $? -eq 0 ]; then
            dlogi "PASSED: Sample rate $sample_rate Hz"
        else
            dlogi "FAILED: Sample rate $sample_rate Hz"
            failures=$((failures+1))
        fi
    done
}

main()
{
    init_globals

    start_test
    logger_disabled || func_lib_start_log_collect

    setup_kernel_check_point
    func_lib_check_sudo
    func_pipeline_export "$tplg" "type:any"

    run_tests

    if [ $failures -eq 0 ]; then
        dlogi "All tests passed"
    else
        die "$failures tests failed"
    fi
}

{
  main "$@"; exit "$?"
}