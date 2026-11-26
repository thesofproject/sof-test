#!/usr/bin/env bash

##
## Case Name: check-src-play
## Preconditions:
##    ffmpeg installed
## Description:
##    Verify sample-rate conversion (SRC) behavior when playing audio at various sample rates and capturing at a fixed 48 kHz rate.
##    The test generates chirp signals at multiple sample rates, plays them back through the DUT, and records the resulting audio as 48 kHz. This validates
##    that the audio pipeline correctly resamples incoming streams and preserves signal integrity across sample-rate boundaries.
## Case steps:
##    1. For each sample rate under test, generate a stereo chirp waveform using ffmpeg at that sample rate.
##    2. Play the generated file through the specified ALSA playback device and record the output with arecord capturing at 48 kHz.
##    3. Save each recorded file into the test log directory for later inspection.
##    4. Analyze the recorded files to ensure the chirp content is present and resampling occurred without errors.
## Expected result:
##    - Playback and capture operations complete without errors for all sample rates.
##    - A recorded file exists for each input sample rate in the log directory.
##    - Recorded files contain the expected chirp content (no severe distortion or silence) and no pipeline errors are observed.
##

set -e

# It is pointless to perf component in HDMI pipeline, so filter out HDMI pipelines
# shellcheck disable=SC2034
NO_HDMI_MODE=true

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['t']='tplg'             OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1               OPT_VAL['t']="$TPLG"

OPT_NAME['p']='playback_device'  OPT_DESC['p']='ALSA pcm playback device. Default: hw:0,2'
OPT_HAS_ARG['p']=1               OPT_VAL['p']='hw:0,2'

OPT_NAME['c']='capture_device'   OPT_DESC['c']='ALSA pcm capture device. Default: hw:0,2'
OPT_HAS_ARG['c']=1               OPT_VAL['c']='hw:0,2'

OPT_NAME['s']='sof-logger'       OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0               OPT_VAL['s']=1

func_opt_parse_option "$@"

init_globals()
{
    tplg=${OPT_VAL['t']}
    playback_dev=${OPT_VAL['p']}
    capture_dev=${OPT_VAL['c']}

    chirp_rates=("350" "700" "1000" "1500" "2000" "2000" "3000" "4000" "4500" "8000" "9000")
    sample_rates=("8000" "16000" "22050" "32000" "44100" "48000" "64000" "88200" "96000" "176400" "192000")
    rec_opt="-f S16_LE -c 2 -r 48000 -d 7"

    all_result_files=()
}

prepare_test_soundfile()
{
    dlogi "Generating test audio: sample rate: $sample_rate Hz, chirp rate: $chirp_rate Hz..."
    mkdir -p "$HOME/Music"
    test_sound_filename="$HOME/Music/${sample_rate}_Hz.wav"
    ffmpeg -loglevel error -y -f lavfi -i "aevalsrc='sin($chirp_rate*t*2*PI*t)':s=$sample_rate:d=5" -ac 2 "$test_sound_filename"
}

run_tests()
{
    failures=0
    set +e
    for i in "${!sample_rates[@]}"
    do
        test_pass=true
        sample_rate=${sample_rates[$i]}
        chirp_rate=${chirp_rates[$i]}
        dlogi "--------------- TEST $((i+1)): PLAY SAMPLE RATE $sample_rate Hz, RECORD IN 48000 Hz ---------------"

        result_filename=$LOG_ROOT/rec_play_$sample_rate.wav
        prepare_test_soundfile
        play_and_record "-D$capture_dev $rec_opt $result_filename" "-D$playback_dev $test_sound_filename"
        if [ $? -eq 1 ]; then
            test_pass=false
            dlogi "TEST $((i+1)) FAIL: aplay/arecord failed, look for previous errors"
        else
            check_soundfile_for_glitches "$result_filename"
            if [ $? -eq 1 ]; then
                test_pass=false
                dlogi "TEST $((i+1)) FAIL: Found glitch in the recording"
            fi
        fi
        if [ "$test_pass" = true ]; then
            dlogi "TEST $((i+1)) PASS: No issues found."
        else
            failures=$((failures+1))
        fi
    done
    set -e

    if [ "$failures" = 0 ]; then
        dlogi "PASS: All testcases passed"
    else
        die "FAIL: $failures testcases failed"
    fi
}

main()
{
    init_globals

    start_test
    if [[ "$TPLG" != *nocodec* ]]; then
        skip_test "Skipping: this test is supported only on NOCODEC platforms."
    fi
    
    logger_disabled || func_lib_start_log_collect

    func_lib_check_sudo
    func_pipeline_export "$tplg" "type:any"

    run_tests
}

{
  main "$@"; exit "$?"
}
