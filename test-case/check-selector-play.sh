#!/bin/bash

##
## Case Name: check-selector-play
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

    rec_opt="-f S16_LE -c 2 -r 48000"
    spk_opt="-r 48000 -F S16_LE -t wav -l 1"

    surroundtest_clip="$HOME/Music/misc/wmv-surroundtest.wav" 
    channel_check_clip="$HOME/Music/misc/Dolby_Digital_Plus_7.1_Channel_Check.wav"

    spktest_2ch_filename="$LOG_ROOT/rec_play_spktest_2ch_s16.wav"
    spktest_1ch_filename="$LOG_ROOT/rec_play_spktest_1ch_s16.wav"
    spktest_6ch_filename="$LOG_ROOT/rec_play_spktest_6ch_s16.wav"
    spktest_8ch_filename="$LOG_ROOT/rec_play_spktest_8ch_s16.wav"

    rec_play_6ch_filename="$LOG_ROOT/rec_play_6ch_s16.wav"
    rec_play_8ch_filename="$LOG_ROOT/rec_play_8ch_s16.wav"

    all_result_files=($spktest_2ch_filename $spktest_1ch_filename $spktest_6ch_filename $spktest_8ch_filename $rec_play_6ch_filename $rec_play_6ch_filename)

    failures=0
}

run_tests()
{
    play_on_speakers_and_record "-D$capture_dev $rec_opt -d 5 $spktest_2ch_filename" "-D$playback_dev $spk_opt -c 2"
    play_on_speakers_and_record "-D$capture_dev $rec_opt -d 4 $spktest_1ch_filename" "-D$playback_dev $spk_opt -c 1"
    play_on_speakers_and_record "-D$capture_dev $rec_opt -d 12 $spktest_6ch_filename" "-D$playback_dev $spk_opt -c 6"
    play_on_speakers_and_record "-D$capture_dev $rec_opt -d 15 $spktest_8ch_filename" "-D$playback_dev $spk_opt -c 8"

    if [ -f "$surroundtest_clip" ]; then
        play_and_record "-D$capture_dev $rec_opt -d 10 $rec_play_6ch_filename" "-D$playback_dev $surroundtest_clip"
    fi

    if [ -f "$channel_check_clip" ]; then
        play_and_record "-D$capture_dev $rec_opt -d 100 $rec_play_8ch_filename" "-D$playback_dev $channel_check_clip"
    fi
    
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