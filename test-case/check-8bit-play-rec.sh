#!/bin/bash

##
## Case Name: check-8bit-play-rec
## Preconditions:
##    - sox installed
## Description:
##    This test verifies 8-bit audio playback and recording functionality using ALSA devices.
##    It generates test chirp signals in multiple 8-bit formats (unsigned 8-bit, A-LAW, MU-LAW), plays them back, records the output,
##    and checks the integrity of the recorded files. The test ensures that the pipeline correctly handles 8-bit audio data for both playback and capture.
## Case steps:
##    1. Generate chirp signals in unsigned 8-bit, A-LAW, MU-LAW, and S32_LE formats using sox.
##    2. Play each chirp file and record the output using arecord and aplay with the specified ALSA devices.
##    3. Convert raw recordings to WAV format for analysis.
##    4. Analyze the recorded files for integrity.
## Expected results:
##    - All chirp files are played and recorded without errors.
##    - The recorded files are successfully generated and converted.
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

    all_result_files=("$u8_play_filename" "$alaw_play_filename" "$mulaw_play_filename" "$u8_rec_filename" "$alaw_rec_filename" "$mulaw_rec_filename")
}

generate_chirps()
{
    dlogi "Generating chirps"
    sox -n --encoding unsigned-integer -b 8 -r 48000 -c 2 "$chirp_u8_filename" synth 5 sine 100+20000 norm -3
    sox -n --encoding a-law -b 8 -r 48000 -c 2 "$chirp_alaw_filename" synth 5 sine 100+20000 norm -3
    sox -n --encoding mu-law -b 8 -r 48000 -c 2 "$chirp_mulaw_filename" synth 5 sine 100+20000 norm -3
    sox -n --encoding signed-integer -b 32 -r 48000 -c 2 "$chirp_s32_filename" synth 5 sine 100+20000 norm -3
}

cleanup()
{
    if [ -f "tmp1.raw" ]; then sudo rm tmp1.raw; fi
    if [ -f "tmp2.raw" ]; then sudo rm tmp2.raw; fi
}

run_tests()
{
    generate_chirps

    set +e
    play_and_record "-D$capture_dev $rec_opt $u8_play_filename" "-D$playback_dev $play_opt -t wav $chirp_u8_filename"
    play_and_record "-D$capture_dev $rec_opt $alaw_play_filename" "-D$playback_dev $play_opt -t raw -f A_LAW $chirp_alaw_filename"
    play_and_record "-D$capture_dev $rec_opt $mulaw_play_filename" "-D$playback_dev $play_opt -t raw -f MU_LAW $chirp_mulaw_filename"

    play_and_record "-D$capture_dev $rec8_opt -f U8 $u8_rec_filename" "-D$playback_dev $chirp_s32_filename"
    play_and_record "-D$capture_dev $rec8_opt -f A_LAW -t raw tmp1.raw" "-D$playback_dev $chirp_s32_filename"
    play_and_record "-D$capture_dev $rec8_opt -f MU_LAW -t raw tmp2.raw" "-D$playback_dev $chirp_s32_filename"
    
    sox --encoding a-law -r 48000 -c 2 tmp1.raw "$alaw_rec_filename"
    sox --encoding u-law -r 48000 -c 2 tmp2.raw "$mulaw_rec_filename"
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
    cleanup
}

{
  main "$@"; exit "$?"
}
