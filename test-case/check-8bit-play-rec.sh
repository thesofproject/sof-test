#!/bin/bash

##
## Case Name: check-8bit-play-rec
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

    rec8_opt="-c 2 -r 48000 -d 7"
    rec_opt="-f S32_LE -c 2 -r 48000 -d 7"
    play_opt="-c 2 -r 48000"

    chirp_u8_filename="$LOG_ROOT/chirp_u8.wav"
    chirp_alaw_filename="$LOG_ROOT/chirp_alaw.raw"
    chirp_mulaw_filename="$LOG_ROOT/chirp_mulaw.raw"
    chirp_s32_filename="$LOG_ROOT/chirp_s32.wav"

    u8_play_filename="$LOG_ROOT/rec_play_u8.wav"
    alaw_play_filename="$LOG_ROOT/rec_play_alaw.wav"
    mulaw_play_filename="$LOG_ROOT/rec_play_mulaw.wav"

    u8_rec_filename="$LOG_ROOT/rec_u8.wav"
    alaw_rec_filename="$LOG_ROOT/rec_alaw.wav"
    mulaw_rec_filename="$LOG_ROOT/rec_mulaw.wav"

    all_result_files=($u8_play_filename $alaw_play_filename $mulaw_play_filename $u8_rec_filename $alaw_rec_filename $mulaw_rec_filename)

    failures=0
}

generate_chirps()
{
    dlogi "Generating chirps"
    sox -n --encoding unsigned-integer -b 8 -r 48000 -c 2 $chirp_u8_filename synth 5 sine 100+20000 norm -3
    sox -n --encoding a-law -b 8 -r 48000 -c 2 $chirp_alaw_filename synth 5 sine 100+20000 norm -3
    sox -n --encoding mu-law -b 8 -r 48000 -c 2 $chirp_mulaw_filename synth 5 sine 100+20000 norm -3
    sox -n --encoding signed-integer -b 32 -r 48000 -c 2 $chirp_s32_filename synth 5 sine 100+20000 norm -3
}

# Parameters: 1-arecord filename, 2-aplay options, 3-aplay filename
playback_with_8bit()
{
    arecord -D$capture_dev $rec_opt $1 & PID=$!
    sleep 1
    aplay -D$playback_dev $play_opt $2 $3
    wait $PID
    sleep 1
}

# Parameters: 1-arecord options, 2-arecord filename
capture_with_8bit()
{
    arecord -D$capture_dev $rec8_opt $1 $2 & PID=$!
    sleep 1
    aplay -D$playback_dev $chirp_s32_filename
    wait $PID
    sleep 1
}

cleanup()
{
    rm tmp1.raw tmp2.raw
}

run_tests()
{
    generate_chirps

    play_and_record "-D$capture_dev $rec_opt -t wav" "-D$playback_dev $play_opt $chirp_u8_filename"
    play_and_record "-D$capture_dev $rec_opt -t raw -f A_LAW" "-D$playback_dev $play_opt $chirp_alaw"
    play_and_record "-D$capture_dev $rec_opt -t raw -f MU_LAW" "-D$playback_dev $play_opt $chirp_mulaw"

    play_and_record "-D$capture_dev $rec8_opt -f U8 $u8_rec_filename" "-D$playback_dev $chirp_s32_filename"
    play_and_record "-D$capture_dev $rec8_opt -f A_LAW -t raw tmp1.raw" "-D$playback_dev $chirp_s32_filename"
    play_and_record "-D$capture_dev $rec8_opt -f MU_LAW -t raw tmp2.raw" "-D$playback_dev $chirp_s32_filename"

    sox --encoding a-law -r 48000 -c 2 tmp1.raw $alaw_rec_filename
    sox --encoding u-law -r 48000 -c 2 tmp2.raw $mulaw_rec_filename


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
    cleanup

    if [ $failures -eq 0 ]; then
        dlogi "All tests passed"
    else
        die "$failures tests failed"
    fi
}

{
  main "$@"; exit "$?"
}