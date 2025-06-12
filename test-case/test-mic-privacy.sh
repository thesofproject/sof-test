#!/bin/bash

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.

##
## Case Name: test-mic-privacy
##
## Preconditions:
##    HW managed mode (Only for DMIC PCH and SNDW interfaces).
##    This test case requires physical loopback between playback and capture.
##    playback <=====> capture
##    USB relay switch is connected. The usbrelay app is installed.
##    Instruction: https://github.com/darrylb123/usbrelay
##
## Description:
##    Run alsabat process perform both playback and capture.
##    Enable MIC privacy.
##    Run alsabat process perform both playback and capture again.
##
## Case step:
##    1. Specify the pcm IDs for playback and capture
##    2. Check if usbrelay is installed and connected properly.
##    3. Run alsabat process perform both playback and capture.
##    4. Switch relay 1 to enable MIC privacy.
##    5. Run alsabat process perform both playback and capture.
##
## Expect result:
##    After step 3 the return value is 0.
##    After step 5 the return value is -1001 (no peak be detected).

TESTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TESTLIB="${TESTDIR}/case-lib"

# shellcheck disable=SC1091 source=case-lib/lib.sh
source "${TESTLIB}/lib.sh"
# shellcheck disable=SC1091 source=case-lib/relay.sh
source "${TESTLIB}/relay.sh"

# remove the existing alsabat wav files
ALSABAT_WAV_FILES="/tmp/mc.wav.*"
rm -f "$ALSABAT_WAV_FILES"

TWO_SECONDS=2

OPT_NAME['p']='pcm_p'     	OPT_DESC['p']='pcm for playback. Example: hw:0,0'
OPT_HAS_ARG['p']=1          OPT_VAL['p']='hw:0,0'

OPT_NAME['N']='channel_p'   OPT_DESC['N']='channel number for playback.'
OPT_HAS_ARG['N']=1          OPT_VAL['N']='2'

OPT_NAME['c']='pcm_c'      	OPT_DESC['c']='pcm for capture. Example: hw:0,1'
OPT_HAS_ARG['c']=1          OPT_VAL['c']='hw:0,1'

OPT_NAME['C']='channel_c'   OPT_DESC['C']='channel number for capture.'
OPT_HAS_ARG['C']=1          OPT_VAL['C']='2'

OPT_NAME['s']='sof-logger'  OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0          OPT_VAL['s']=1

OPT_NAME['r']='rate'        OPT_DESC['r']='sample rate'
OPT_HAS_ARG['r']=1          OPT_VAL['r']=48000

OPT_NAME['u']='relay'       OPT_DESC['u']='name of usbrelay switch, default value is HURTM_1'
OPT_HAS_ARG['u']=1          OPT_VAL['u']='HURTM_1'

func_opt_parse_option "$@"

pcm_p=${OPT_VAL['p']}
pcm_c=${OPT_VAL['c']}
channel_c=${OPT_VAL['C']}
channel_p=${OPT_VAL['N']}
rate=${OPT_VAL['r']}
relay=${OPT_VAL['u']}

dlogi "Params: pcm_p=$pcm_p, pcm_c=$pcm_c, channel_c=$channel_c, channel_p=$channel_p, rate=$rate, LOG_ROOT=$LOG_ROOT"

__upload_wav_files()
{
    # upload the alsabat wav file
    for file in $ALSABAT_WAV_FILES; do
        # alsabat has a bug where it creates an empty record in playback mode
        if test -s "$file"; then
            cp -v "$file" "$LOG_ROOT/"
        fi
    done
}

check_playback_capture()
{
    # check if capture and playback work
    dlogc "alsabat -P$pcm_p -C$pcm_c -c 2 -r $rate"
    alsabat -P"$pcm_p" -C"$pcm_c" -c 2 -r "$rate" || {
        # upload failed wav file
        __upload_wav_files
        die "alsabat failed"
    }
}

main()
{
    setup_kernel_check_point

    start_test

    logger_disabled || func_lib_start_log_collect

    if [ -z "$pcm_p" ] || [ -z "$pcm_c" ]; then
        skip_test "No playback or capture PCM is specified. Skip the $0 test."
    fi

    # check if usbrelay tool is installed
    command -v usbrelay || {
        skip_test "usbrelay command not found. Please install usbrelay to control the mic privacy switch."
    }

    check_locale_for_alsabat

    # reset sof volume to 0dB
    reset_sof_volume

    # If MODEL is defined, set proper gain for the platform
    if [ -z "$MODEL" ]; then
        # treat as warning only
        dlogw "NO MODEL is defined. Please define MODEL to run alsa_settings/MODEL.sh"
    else
        dlogi "apply alsa settings for alsa_settings/MODEL.sh"
        set_alsa_settings "$MODEL"
    fi

    dlogi "Reset - Turn off the mic privacy"
    usbrelay_switch "$relay" 0

    # wait for the switch to settle
    sleep "$TWO_SECONDS"

    # check the PCMs before mic privacy test
    dlogi "Check playback/capture before mic privacy test"
    check_playback_capture

    # Select the first card
    first_card_name=$(aplay -l | awk '/^card ([0-9]+)/ {print $3; exit}')
    # dump amixer contents always.
    # Good case amixer settings is for reference, bad case for debugging.
    amixer -c "${first_card_name}" contents > "$LOG_ROOT"/amixer_settings.txt

    check_playback_capture

    sleep "$TWO_SECONDS"

    dlogi "===== Testing: MIC privacy ====="
    dlogi "Turn on the mic privacy switch"
    usbrelay_switch "$relay" 1

    # wait for the switch to settle
    sleep "$TWO_SECONDS"

    alsabat_output=$(mktemp)
    dlogc "alsabat -P$pcm_p -C$pcm_c -c 2 -r $rate"
    # Run alsabat and capture both output and exit status
    alsabat_status=0
    alsabat -P"$pcm_p" -C"$pcm_c" -c 2 -r "$rate" > "$alsabat_output" 2>&1 || {
        alsabat_status=$?
    }

    case "$alsabat_status" in
        23)
            # alsabat returns 23 if no peak detected (expected for MIC privacy)
            if grep -q -e "Amplitude: 0.0; Percentage: \[0\]" -e "Return value is -1001" "$alsabat_output"; then
                dlogi "Alsabat output indicates zero signal as expected (MIC privacy works)."
            else
                dloge "alsabat failed with status $alsabat_status, but signal is not zero."
                __upload_wav_files
                die "alsabat failed with: $(cat "$alsabat_output")."
            fi
            ;;
        0)
            dloge "The alsabat command was unexpectedly successful."
            __upload_wav_files
            die "MIC privacy doesn't work. alsabat output: $(cat "$alsabat_output")"
            ;;
        *)
            dloge "The alsabat command failed with unexpected status $alsabat_status."
            __upload_wav_files
            die "alsabat failed with: $(cat "$alsabat_output")."
            ;;
    esac

    dlogi "Turn off the mic privacy switch."
    usbrelay_switch "$relay" 0

    check_playback_capture

    dlogi "===== Test completed successfully. ====="

    rm -rf "$alsabat_output"

    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
}

{
  main "$@"; exit "$?"
}
