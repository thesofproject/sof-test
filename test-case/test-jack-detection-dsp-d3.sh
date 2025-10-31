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
# The unplugging and plugging of the jack is when DSP is in D3 state (suspend)
# to ensure the system can handle jack detection events correctly.
# The test will check if the jack detection status is updated correctly
# when the jack is plugged in and unplugged and if DSP status is changing
# correctly as well.


TESTDIR=$(realpath -e "$(dirname "${BASH_SOURCE[0]}")/..")
TESTLIB="${TESTDIR}/case-lib"

DSP_SUSPEND_TIMEOUT=15

# shellcheck disable=SC1091 source=case-lib/lib.sh
source "${TESTLIB}/lib.sh"
# shellcheck disable=SC1091 source=case-lib/relay.sh
source "${TESTLIB}/relay.sh"

# shellcheck disable=SC2153
OPT_NAME['t']='tplg'                OPT_DESC['t']="tplg file, default value is env TPLG: $TPLG"
OPT_HAS_ARG['t']=1                  OPT_VAL['t']="$TPLG"

OPT_NAME['l']='loop'                OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1                  OPT_VAL['l']=1

OPT_NAME['s']='sof-logger'          OPT_DESC['s']="open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0                  OPT_VAL['s']=1

OPT_NAME['d']='dsp-settle-sleep'    OPT_DESC['d']='waiting time to change DSP state'
OPT_HAS_ARG['d']=1                  OPT_VAL['d']=5

OPT_NAME['r']='relay-settle-sleep'  OPT_DESC['r']='waiting time to stabilize after relay change state'
OPT_HAS_ARG['r']=1                  OPT_VAL['r']=1

OPT_NAME['u']='relay'               OPT_DESC['u']='name of usbrelay switch, default value is HURTM_2'
OPT_HAS_ARG['u']=1                  OPT_VAL['u']='HURTM_2'

OPT_NAME['H']='headphone'           OPT_DESC['H']='name of pcm control for headphone jack'
OPT_HAS_ARG['H']=1                  OPT_VAL['H']='headphone jack'

OPT_NAME['M']='headset'             OPT_DESC['M']='name of pcm control for headset mic jack'
OPT_HAS_ARG['M']=1                  OPT_VAL['M']='headset [a-z ]*jack'

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
relay=${OPT_VAL['u']}
loop_cnt=${OPT_VAL['l']}
dsp_settle_time=${OPT_VAL['d']}
relay_settle_time=${OPT_VAL['r']}
headphone_jack_name=${OPT_VAL['H']}
headset_mic_jack_name=${OPT_VAL['M']}


func_check_dsp_status()
{
    dlogi "Wait for DSP power status to become suspended"
    for i in $(seq 1 "$1")
    do
        # Here we pass a hardcoded 0 to python script, and need to ensure
        # DSP is the first audio pci device in 'lspci', this is true unless
        # we have a third-party pci sound card installed.
        [[ $(sof-dump-status.py --dsp_status 0) == "suspended" ]] && break
        sleep 1
        if [ "$i" -eq "$1" ]; then
            die "DSP is not suspended after $1s, end test"
        fi
    done
    dlogi "DSP suspended in ${i}s"
}

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

    if [ "$expected_control_state" = "$control_state" ]; then
        return 0
    else
        dloge "Expected control state ($expected_control_state) but got ($control_state)."
        return 1
    fi
}

testing_one_pcm()
{
    dlogi "===== Testing: (Round: $i/$loop_cnt) (PCM: $pcm [$dev]<$type>) ====="
    dlogi "DEVICE: $dev, TYPE: $type, PCM: $pcm, RATE: $rate, CHANNEL: $channel"

    local dsp_status
    local timeout=0
    while [ "$timeout" -lt "$DSP_SUSPEND_TIMEOUT" ] ; do
        dsp_status=$(sof-dump-status.py --dsp_status 0)
        if [ "$dsp_status" = "suspended" ] ; then
            break
        fi
        dlogi "Current DSP status is $dsp_status, waiting for it to be suspended..."
        sleep 1
        timeout=$((timeout + 1))
    done

    if [ "$dsp_status" != "suspended" ] ; then
        die "Current DSP status ($dsp_status) is not suspended."
    fi

    dlogi "Unplug jack audio."
    usbrelay_switch "$relay" 1

    dlogi "Wait for ${relay_settle_time}s to ensure jack detection is off"
    sleep "$relay_settle_time"

    if ! check_control_switch_state "$headset_mic_jack_name" "off"; then
        die "unplug $headset_mic_jack_name failed."
    fi

    if ! check_control_switch_state "$headphone_jack_name" "off"; then
        die "unplug $headphone_jack_name failed."
    fi

    func_check_dsp_status "$dsp_settle_time"

    dlogi "Plug jack audio."
    usbrelay_switch "$relay" 0

    dlogi "Wait for ${relay_settle_time}s to ensure jack detection is on"
    sleep "$relay_settle_time"

    if ! check_control_switch_state "$headset_mic_jack_name" "on"; then
        die "Plug $headset_mic_jack_name failed."
    fi

    if ! check_control_switch_state "$headphone_jack_name" "on"; then
        die "Plug $headphone_jack_name failed."
    fi

    func_check_dsp_status "$dsp_settle_time"
}

main()
{
    func_pipeline_export "$tplg" "type:playback"

    setup_kernel_check_point

    start_test

    dlogi "Checking usbrelay availability..."
    if ! command -v usbrelay > /dev/null; then
        # If usbrelay package is not installed
        skip_test "usbrelay command not found."
    fi

    if ! usbrelay_switch --debug > /dev/null; then
        skip_test "Failed to get usbrelay status."
    fi

    dlogi "Reset USB Relay - plug jack audio."
    usbrelay_switch "$relay" 0

    for idx in $(seq 0 $((PIPELINE_COUNT - 1)))
    do
        initialize_audio_params "$idx"

        if [[ "$pcm" != *"Jack"* ]] ; then
            dlogi "PCM $pcm is not a Jack, skipping..."
            continue
        fi

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
