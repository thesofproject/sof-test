#!/bin/bash

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2021-2025 Intel Corporation. All rights reserved.

# needs usbrelay package: https://github.com/darrylb123/usbrelay
# param1: --debug | switch name
# param2: switch state
usbrelay_switch()
{
    if [[ "$1" == "--debug" ]]; then
        dlogi "Debug mode: Current status of all relays:"
        usbrelay || {
            die "Failed to get usbrelay status.
            The usbrelay hw module is not responding or no relays detected.
            Check hardware connection."
        }
    fi

    # Declare a constant for the relay settle time
    local USBRELAY_SETTLE_TIME=0.5

    local switch_name=$1
    local state=$2

    dlogi "Setting usbrelay switch $switch_name to $state."
    usbrelay "$switch_name=$state" --quiet || {
        die "Failed to set usbrelay switch $switch_name to $state.
        The usbrelay hw module is not responding or no relays detected.
        Check hardware connection."
    }

    # wait for the switch to settle
    sleep "$USBRELAY_SETTLE_TIME"

    # Display current state of the switch
    current_state=$(usbrelay | awk -F= -v name="$switch_name" '$1 == name { print $2 }')

    # Check if current_state is equal to the requested state
    [[ "$current_state" == "$state" ]] || {
        die "usbrelay switch $switch_name failed to set to $state (current: $current_state)"
    }

    case "$current_state" in
        '1') dlogi "Current state of $switch_name is: on";;
        '0') dlogi "Current state of $switch_name is: off";;
        *) die "Invalid state for $switch_name: $current_state";;
    esac
}
