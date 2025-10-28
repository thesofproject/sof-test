#!/bin/bash

##
## Case Name: check-float-play-rec
## Preconditions:
##    - sox installed
## Description:
##    Verify float audio playback and capture using ALSA devices. The test generates a float-encoded chirp and a 32-bit signed integer chirp,
##    plays one while recording the other format and vice versa. This validates that the audio pipeline correctly handles FLOAT and S32_LE sample formats
##    and that sample conversion between formats works as expected.
## Case steps:
##    1. Generate a 48 kHz stereo chirp in 32-bit float and 32-bit signed integer formats using sox.
##    2. Use arecord/aplay to play the float chirp and record with S32_LE format, then play the S32_LE chirp and record with FLOAT_LE format.
##    3. Save both recorded files into the log directory for later analysis.
##    4. Analyze the recorded files for integrity and correct format.
## Expected results:
##    - Both playback and recording complete without errors.
##    - The recorded files are created in the log directory and match expected sample formats.
##    - No failures are reported during analysis.
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

    rec_opt="-c 2 -r 48000 -d 7"

    chirp_float_filename="$LOG_ROOT/chirp_float_48k.wav"
    chirp_s32_filename="$LOG_ROOT/chirp_s32_48k.wav"

    rec_play_filename="$LOG_ROOT/rec_play_float.wav"
    rec_filename="$LOG_ROOT/rec_float.wav"

    all_result_files=("$rec_play_filename" "$rec_filename")
}

generate_chirps()
{
    dlogi "Generating chirps"
    sox -n --encoding float -r 48000 -c 2 -b 32 "$chirp_float_filename" synth 5 sine 100+20000 norm -3
    sox -n --encoding signed-integer -L -r 48000 -c 2 -b 32 "$chirp_s32_filename" synth 5 sine 100+20000 norm -3
}

run_tests()
{
    generate_chirps

    set +e
    play_and_record "-D$capture_dev $rec_opt -f S32_LE $rec_play_filename" "-D$playback_dev $chirp_float_filename"
    play_and_record "-D$capture_dev $rec_opt -f FLOAT_LE $rec_filename" "-D$playback_dev $chirp_s32_filename"
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
