#!/bin/bash

##
## Case Name: check-selector-play
## Preconditions:
##    - hardware or software loopback is available
## Description:
##    Verify the selector/mixing behavior of playback pipelines when routing audio to different speaker configurations
##    (mono, stereo, 5.1/6ch, 7.1/8ch). The test plays coresponding test sound files and records
##    the output from the capture device to validate channel routing.
## Case steps:
##    1. Play 1,2,6 and 8-channel sounds.
##    2. Record the output on 2 channels.
##    5. Save recorded files and run automated checks for channel presence.
## Expected result:
##    - Playback and recording complete without errors for each tested channel configuration.
##    - Recorded files exist for each test and contain the expected channel information (all the sounds from original file is present in output file).
##

set -e

# It is pointless to perf component in HDMI pipeline, so filter out HDMI pipelines
# shellcheck disable=SC2034
NO_HDMI_MODE=true

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['t']='tplg'             OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1               OPT_VAL['t']="$TPLG"

OPT_NAME['p']='playback_device'  OPT_DESC['p']='ALSA pcm playback device. Example: hw:0,1'
OPT_HAS_ARG['p']=1               OPT_VAL['p']=''

OPT_NAME['c']='capture_device'   OPT_DESC['c']='ALSA pcm capture device. Example: hw:0,1'
OPT_HAS_ARG['c']=1               OPT_VAL['c']=''

OPT_NAME['s']='sof-logger'       OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0               OPT_VAL['s']=1

func_opt_parse_option "$@"

init_globals()
{
    tplg=${OPT_VAL['t']}
    playback_dev=${OPT_VAL['p']}
    capture_dev=${OPT_VAL['c']}

    channels_to_test=(1 2 6 8)

    rec_opt="-f S16_LE -c 2 -r 48000"

    failures=0
}

# Arguments: the number of channels soundfile should have
generate_soundfile()
{
    ch_nr="$1"
    if python3 "$SCRIPT_HOME"/tools/test-sound-generator.py "$1"; then
        dlogi "Testfile generated."
        return 0
    else
        dlogw "Error generating testfile"
        return 1
    fi
}

# Checks for soundfiles needed for test, generates missing ones
prepare_test_soundfiles()
{
    mkdir -p "$HOME/Music"
    for ch_nr in "${channels_to_test[@]}"
    do
        filename="$HOME/Music/${ch_nr}_channels_test.wav"
        if [ ! -f "$filename" ]; then
            generate_soundfile "$ch_nr"
        fi
    done
}

run_tests()
{
    set +e
    for ch_nr in "${channels_to_test[@]}"
    do
        test_filename="$HOME/Music/${ch_nr}_channels_test.wav"
        result_filename="$LOG_ROOT/rec_${ch_nr}ch.wav"

        play_and_record "-D$capture_dev $rec_opt -d 25 $result_filename" "-Dplug$playback_dev $test_filename"

        if ! analyze_mixed_sound "$result_filename" "$ch_nr"; then
            failures=$((failures+1))
        fi
    done
    set -e

    if [ $failures -eq 0 ]; then
        dlogi "All files correct"
    else
        die "Detected corrupted files!"
    fi

}

main()
{
    init_globals
    start_test

    if [[ "$tplg" != *nocodec* ]]; then
        skip_test "Skipping: test currently supported for NO-CODEC platforms only"
    fi
    prepare_test_soundfiles

    logger_disabled || func_lib_start_log_collect

    setup_kernel_check_point
    func_lib_check_sudo
    func_pipeline_export "$tplg" "type:any"

    run_tests
}

{
  main "$@"; exit "$?"
}
