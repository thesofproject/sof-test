#!/bin/bash

##
## Case Name: check-src-rec
## Preconditions:
##    ffmpeg installed
## Description:
##    Verify sample-rate conversion (SRC) for capture paths by playing a reference 48 kHz chirp and recording it at a variety of lower and higher sample rates.
##    This ensures the capture pipeline correctly resamples incoming audio from a fixed playback sample rate to requested capture rates.
## Case steps:
##    1. Generate a 48 kHz stereo chirp signal using ffmpeg and store it in the test log directory.
##    2. For each sample rate under test, play the 48 kHz chirp and record using arecord at the target sample rate.
##    3. Save recorded files for each sample rate to the log directory for later inspection.
##    4. Analyze the recorded files to confirm the chirp content is present and resampling is performed without major artifacts.
## Expected result:
##    - Playback and capture operations succeed for all tested sample rates.
##    - A recorded file exists for each requested sample rate in the log directory.
##    - Recorded files contain the expected chirp (no severe distortion or silence) and no pipeline errors are observed.
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

    sample_rates=("8000" "16000" "22050" "32000" "44100" "48000")

    rec_opt="-f S16_LE -c 2 -d 7"

    test_sound_filename=$LOG_ROOT/play.wav
    all_result_files=()
}

run_tests()
{
    dlogi "Generate 48 kHz chirp 0 - 20 kHz"
    ffmpeg -y -f lavfi -i "aevalsrc='sin(2000*t*2*PI*t)':s=48000:d=5" -ac 2 "$test_sound_filename"

    set +e
    for i in "${!sample_rates[@]}"
    do
        sample_rate=${sample_rates[$i]}

        result_filename=$LOG_ROOT/rec_$sample_rate.wav
        all_result_files+=("$result_filename")
        play_and_record "-D$capture_dev $rec_opt -r $sample_rate $result_filename" "-D$playback_dev $test_sound_filename"
    done
    set -e

    if check_soundfile_for_glitches "${all_result_files[@]}"; then
        dlogi "All files correct"
    else
        die "Detected corrupted files!"
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

    setup_kernel_check_point
    func_lib_check_sudo
    func_pipeline_export "$tplg" "type:any"

    run_tests
}

{
  main "$@"; exit "$?"
}
