#!/bin/bash

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.

##
## Preconditions
# 1. Runtime PM status is on.
# 2. aplay (playback) and arecord (capture) is running.
# 3. USB relay switch is available and configured.
#    Jack detection header should be connected to the USB relay switch
#    to the port HURTM_2 (NC) connector.

## Test Description
# * Set Jack detection relay to state off (0), play/record and determine if
# status is updated as expected. The status should be on.
# Also alsabat command should return 0.
# * Set Jack detection relay to state on (1), play/record and determine if
# status is updated as expected. The status should be off.
# Also alsabat command should return -1001.
# * Repeat for both headphone and headset jacks.
# * Repeat for both HDMI and DisplayPort if available.

## Case Steps
# 1. Ensure the USB relay switch is configured to control the jack detection header.
# 2. Set the USB relay switch to state off (0), simulate plugging in the headset.
# 3. Run aplay/arecord command to play/record audio.
# 4. Check the jack detection status via amixer. The status should indicate **on**.
# 5. Set the USB relay switch to state on (1), simulate unplugging the headset from the jack.
# 6. Check the jack detection status via amixer. The status should indicate **off**.
# 7. Check dmesg for any unexpected errors.
#
# Repeat for both headphone and headset jacks.
# Repeat for all pipelines.

TESTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TESTLIB="${TESTDIR}/case-lib"

# shellcheck source=case-lib/lib.sh
source "${TESTLIB}/lib.sh"
source "${TESTLIB}/relay.sh"

OPT_NAME['t']='tplg'       OPT_DESC['t']="tplg file, default value is env TPLG: $TPLG"
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['d']='duration'   OPT_DESC['d']='arecord duration in second'
OPT_HAS_ARG['d']=1         OPT_VAL['d']=2

OPT_NAME['l']='loop'       OPT_DESC['l']='option of speaker-test'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=3

OPT_NAME['s']='sof-logger' OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0         OPT_VAL['s']=1

OPT_NAME['R']='relay'      OPT_DESC['R']='name of usbrelay switch, default value is HURTM_2'
OPT_HAS_ARG['R']=1         OPT_VAL['R']="HURTM_2"

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
duration=${OPT_VAL['d']}
relay=${OPT_VAL['R']}

check_control_switch_state()
{
    # Check the state of the switch using amixer.
    # The switch name is passed as the first argument, and the expected state (on/off)
    # is passed as the second argument.
    # Returns 0 if the state matches, 1 otherwise.
    local switch_name="$1"
    local expected_switch_state="$2"
    local switch_state

    switch_state=$(echo -e $(amixer -c 0 contents | grep -i "$switch_name .* *jack" -A 2) | sed -n '1s/^.*values=//p')
    dlogi "$switch_name switch is: $switch_state"

    if [[ "$expected_switch_state" == "$switch_state" ]]; then
        return 0
    else
        return 1
    fi
}

main()
{
    func_pipeline_export "$tplg" "type:playback"

    setup_kernel_check_point

    start_test

    logger_disabled || func_lib_start_log_collect

    # check if usbrelay tool is installed
    command -v usbrelay || {
        skip_test "usbrelay command not found. Please install usbrelay to control the mic privacy switch."
    }

    dlogi "Reset - plug jack audio"
    usbrelay_switch "$relay" 0

    for idx in $(seq 0 $((PIPELINE_COUNT - 1)))
    do
        initialize_audio_params "$idx"

        channel=$(func_pipeline_parse_value "$idx" channel)
        rate=$(func_pipeline_parse_value "$idx" rate)
        fmt=$(func_pipeline_parse_value "$idx" fmt)
        dev=$(func_pipeline_parse_value "$idx" dev)
        snd=$(func_pipeline_parse_value "$idx" snd)

        dlogi "===== Testing: (PCM: $pcm [$dev]<$type>) ====="

        aplay_opts -D"$dev" -r "$rate" -c "$channel" -f "$fmt" -d "$duration" "/dev/zero" -q || {
            func_lib_lsof_error_dump "$snd"
            die "aplay on PCM $dev failed."
        }

        dlogi "Unplug jack audio."
        usbrelay_switch "$relay" 1

        aplay_opts -D"$dev" -r "$rate" -c "$channel" -f "$fmt" -d "$duration" "/dev/zero" -q || {
            func_lib_lsof_error_dump "$snd"
            die "aplay on PCM $dev failed."
        }

        check_control_switch_state "headset" "off" || {
            die "unplug headset jack failed."
        }

        check_control_switch_state "headphone" 'off' || {
            die "unplug headphone jack failed."
        }

        dlogi "Plug jack audio."
        usbrelay_switch "$relay" 0

        aplay_opts -D"$dev" -r "$rate" -c "$channel" -f "$fmt" -d "$duration" "/dev/zero" -q || {
            func_lib_lsof_error_dump "$snd"
            die "aplay on PCM $dev failed."
        }

        check_control_switch_state "headset" "on" || {
            die "Plug headset jack failed."
        }

        check_control_switch_state "headphone" "on" || {
            die "Plug headphone jack failed."
        }
    done

    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
}

{
    main "$@"; exit "$?"
}
