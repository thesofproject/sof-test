#!/bin/bash

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2021-2025 Intel Corporation. All rights reserved.

# test-mic_privacy.sh needs to control mic privacy settings (on/off)
# needs usbrelay package: https://github.com/darrylb123/usbrelay
# param1: switch name
# param2: switch state
usbrelay_switch()
{
    # Declare a constant for the relay settle time
    USBRELAY_SETTLE_TIME=0.5

    local switch_name=$1
    local state=$2

    # Check if usbrelay is installed
    command -v usbrelay || {
        # If usbrelay package is not installed
        skip_test "usbrelay command not found. Please install usbrelay package."
    }

    dlogi "Setting usbrelay switch $switch_name to $state."
    usbrelay "$switch_name=$state" || {
        # if not detect relays hw module, skip the test
        die "Failed to set usbrelay switch $switch_name to $state.
        The usbrelay hw module is not responding or no relays detected.
        Check hardware connection."
    }

    # wait for the switch to settle
    sleep "$USBRELAY_SETTLE_TIME"

    # Display current state of the switch
    current_state=$(usbrelay | grep "$switch_name" | awk -F= '{print $2}')

    # Check if current_state is equal to the requested state
    [[ "$current_state" == "$state" ]] || {
        die "usbrelay switch $switch_name failed to set to $state (current: $current_state)"
    }

    if [[ "$current_state" == "1" ]]; then
        dlogi "Current state of $switch_name is: on"
    elif [[ "$current_state" == "0" ]]; then
        dlogi "Current state of $switch_name is: off"
    else
        die "Invalid state for $switch_name: $current_state"
    fi
}
