#!/bin/bash

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

    chirp_rates=("350" "700" "1000" "1500" "2000" "2000" "3000" "4000" "4500" "8000" "9000")
    sample_rates=("8000" "16000" "22050" "32000" "44100" "48000" "64000" "88200" "96000" "176400" "192000")
    rec_opt="-f S16_LE -c 2 -r 48000 -d 7"

    all_result_files=()
}

run_tests()
{
    set +e
    for i in "${!sample_rates[@]}"
    do
        sample_rate=${sample_rates[$i]}
        chirp_rate=${chirp_rates[$i]}

        test_sound_filename=$LOG_ROOT/play.wav
        result_filename=$LOG_ROOT/rec_play_$sample_rate.wav
        all_result_files+=("$result_filename")

        dlogi "Play $sample_rate Hz chirp 0 - $chirp_rate Hz, capture as 48 kHz"
        ffmpeg -y -f lavfi -i "aevalsrc='sin($chirp_rate*t*2*PI*t)':s=$sample_rate:d=5" -ac 2 "$test_sound_filename"  #TODO: maybe separate dir for artifacts ??

        play_and_record "-D$capture_dev $rec_opt $result_filename" "-D$playback_dev $test_sound_filename"
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
    logger_disabled || func_lib_start_log_collect

    setup_kernel_check_point
    func_lib_check_sudo
    func_pipeline_export "$tplg" "type:any"

    run_tests
}

{
  main "$@"; exit "$?"
}
