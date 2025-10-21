#!/bin/bash

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.

##
## Preconditions
# USB relay switch is available and configured.
# Jack detection header should be connected to the USB relay switch
# to the port HURTM_2 (NC) connector.

## Test Description
# Verify jack detection functionality by simulating plugging and unplugging
# of audio jack using a USB relay switch.
# The unplugging and plugging of the jack will be during playback operations
# to ensure the system can handle jack detection events correctly.
# The test will check if the jack detection status is updated correctly
# when the jack is plugged in and unplugged.

## Case Steps
# 1. Ensure the USB relay switch is configured to control the jack detection header.
# 2. Ensure the aplay (playback) command works properly.
# 3. Set the USB relay switch to state on (1), simulate unplugging the headset from the jack.
# 4. Check the jack detection status via amixer. The status should indicate **off**.
# 5. Check if the aplay process is still running after unplugging the jack.
#    If the process is not running, the test fails.
#    If the process is still running, continue to the next step.
# 6. Set the USB relay switch to state off (0), simulate plugging the headset.
# 7. Check the jack detection status via amixer. The status should indicate **on**.
# 8. Check if the aplay process is still running after plugging the jack.
#    If the process is not running, the test fails.
#    If the process is still running, continue to the next step.
# 9. Terminate the aplay process.
# 10. Check if the aplay process is terminated successfully.
#    If the process is still running, the test fails.
#    If the process is terminated successfully, the test passes.
# 11. Check dmesg for any unexpected errors.
#
# Repeat steps 3-11 for all pcm jack playback devices.

TESTDIR=$(realpath -e "$(dirname "${BASH_SOURCE[0]}")/..")
TESTLIB="${TESTDIR}/case-lib"

# shellcheck disable=SC1091 source=case-lib/lib.sh
source "${TESTLIB}/lib.sh"
# shellcheck disable=SC1091 source=case-lib/relay.sh
source "${TESTLIB}/relay.sh"

# shellcheck disable=SC2153
OPT_NAME['t']='tplg'                OPT_DESC['t']="tplg file, default value is env TPLG: $TPLG"
OPT_HAS_ARG['t']=1                  OPT_VAL['t']="$TPLG"

OPT_NAME['l']='loop'                OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1                  OPT_VAL['l']=1

OPT_NAME['s']='sof-logger'          OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0                  OPT_VAL['s']=1

OPT_NAME['d']='dsp-settle-sleep'    OPT_DESC['d']="Waitng time to change control state"
OPT_HAS_ARG['d']=1                  OPT_VAL['d']=3

OPT_NAME['u']='relay'               OPT_DESC['u']='name of usbrelay switch, default value is HURTM_2'
OPT_HAS_ARG['u']=1                  OPT_VAL['u']="HURTM_2"

OPT_NAME['H']='headphone'           OPT_DESC['H']='name of pcm control for headphone jack'
OPT_HAS_ARG['H']=1                  OPT_VAL['H']="headphone jack"

OPT_NAME['M']='headset'             OPT_DESC['M']='name of pcm control for headset mic jack'
OPT_HAS_ARG['M']=1                  OPT_VAL['M']="headset [a-z ]*jack"

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
relay=${OPT_VAL['u']}
loop_cnt=${OPT_VAL['l']}
dsp_settle_time=${OPT_VAL['d']}
headphone_jack_name=${OPT_VAL['H']}
headset_mic_jack_name=${OPT_VAL['M']}

check_control_switch_state()
{
    # Check the state of the switch using amixer.
    # The switch name is passed as the first argument, and the expected state (on/off)
    # is passed as the second argument.
    # Returns 0 if the state matches, 1 otherwise.
    local control_name="$1"
    local expected_control_state="$2"
    local control_state

    dlogi "Check if the state of control: $control_name is correct."
    control_state=$(amixer -c "$SOFCARD" contents | \
                        gawk -v name="$control_name" -f "${TESTLIB}/control_state.awk")
    dlogi "$control_name switch is: $control_state"

    if [[ "$expected_control_state" == "$control_state" ]]; then
        return 0
    else
        dloge "Expected control state ($expected_control_state) but got ($control_state)."
        return 1
    fi
}

testing_one_pcm()
{
    dlogi "===== Testing: (PCM: $pcm [$dev]<$type>) (Loop: $i/$loop_cnt) ====="
    dlogi "DEVICE: $dev, TYPE: $type, PCM: $pcm, RATE: $rate, CHANNEL: $channel"

    dlogi "Command: aplay -Dplug$dev -q /dev/zero"
    # Start alsabat in background with longer duration
    dlogi "Starting aplay in background..."
    aplay "-Dplug$dev" -d10 -q /dev/zero & pid_playback=$! || {
        func_lib_lsof_error_dump "$snd"
        die "Failed to start aplay on PCM: $pcm"
    }
    # Wait briefly to ensure the device is ready and avoid read errors
    sleep 1
    dlogi "aplay started with PID: $pid_playback"

    dlogi "Unplug jack audio."
    usbrelay_switch "$relay" 1

    # Wait for a short period to allow the system to detect the unplug event
    sleep "$dsp_settle_time"

    # check if the aplay process is still running after unplugging the jack
    ps -p "$pid_playback" > /dev/null || {
        func_lib_lsof_error_dump "$snd"
        die "Playback process terminated unexpectedly after unplugging the jack."
    }

    check_control_switch_state "$headset_mic_jack_name" "off" || {
        die "unplug $headset_mic_jack_name jack failed."
    }

    check_control_switch_state "$headphone_jack_name" "off" || {
        die "unplug $headphone_jack_name jack failed."
    }

    dlogi "Plug jack audio."
    usbrelay_switch "$relay" 0

    # Wait for a short period to allow the system to detect the plug event
    sleep "$dsp_settle_time"

    # check if the aplay process is still running after unplugging the jack
    ps -p "$pid_playback" > /dev/null || {
        func_lib_lsof_error_dump "$snd"
        die "Playback process terminated unexpectedly after plugging the jack."
    }

    check_control_switch_state "$headset_mic_jack_name" "on" || {
        die "Plug $headset_mic_jack_name failed."
    }

    check_control_switch_state "$headphone_jack_name" "on" || {
        die "Plug $headphone_jack_name jack failed."
    }

    kill -9 $pid_playback > /dev/null 2>&1
    wait $pid_playback 2>/dev/null || true
    ps -p "$pid_playback" > /dev/null && {
        dloge "Failed to kill playback process."
        func_lib_lsof_error_dump "$snd"
        die "Playback process did not terminate as expected."
    }
    dlogi "Playback process terminated."
    dlogi "===== Testing: PASSED ====="
}

main()
{
    func_pipeline_export "$tplg" "type:playback"

    setup_kernel_check_point

    start_test

    dlogi "Checking usbrelay availability..."
    command -v usbrelay || {
        # If usbrelay package is not installed
        skip_test "usbrelay command not found."
    }

    # display current status of relays
    usbrelay_switch --debug || {
        skip_test "Failed to get usbrelay status."
    }

    logger_disabled || func_lib_start_log_collect

    dlogi "Reset - plug jack audio"
    usbrelay_switch "$relay" 0

    dlogi "Headphone patten: $headphone_jack_name"
    dlogi "Headset mic pattern: $headset_mic_jack_name"

    for idx in $(seq 0 $((PIPELINE_COUNT - 1)))
    do
        initialize_audio_params "$idx"

        [[ "$pcm" == *Jack* ]] || {
            dlogi "PCM $pcm is not a Jack, skipping..."
            continue
        }

        for i in $(seq 1 "$loop_cnt")
        do
            testing_one_pcm
            sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
            setup_kernel_check_point
        done
    done
}

{
    main "$@"; exit "$?"
}
