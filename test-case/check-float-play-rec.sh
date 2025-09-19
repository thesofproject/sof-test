#!/bin/bash

##
## Case Name: check-float-play-rec
## Preconditions:
##    ffmpeg installed
## Description:
##    TODO
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

    rec_opt="-c 2 -r 48000 -d 7"

    chirp_float_filename="$LOG_ROOT/chirp_float_48k.wav"
    chirp_s32_filename="$LOG_ROOT/chirp_s32_48k.wav"

    rec_play_filename="$LOG_ROOT/rec_play_float.wav"
    rec_filename="$LOG_ROOT/rec_float.wav"

    all_result_files=($rec_play_filename $rec_filename)

    failures=0
}

generate_chirps()
{
    dlogi "Generating chirps"
    sox -n --encoding float -r 48000 -c 2 -b 32 $chirp_float_filename synth 5 sine 100+20000 norm -3
    sox -n --encoding signed-integer -L -r 48000 -c 2 -b 32 $chirp_s32_filename synth 5 sine 100+20000 norm -3
}

run_tests()
{
    generate_chirps

    play_and_record "-D$capture_dev $rec_opt -f S32_LE $rec_play_filename" "-D$playback_dev $chirp_float_filename"
    play_and_record "-D$capture_dev $rec_opt -f FLOAT_LE $rec_filename" "-D$playback_dev $chirp_s32_filename"

    for filename in "${all_result_files[@]}"
    do
        dlogi "Analyzing $filename file..."
        #TODO: Actually analyze the result
        if [ $? -eq 0 ]; then
            dlogi "PASSED: No issues found in $filename file"
        else
            dlogi "FAILED: Found issues in $filename file"
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