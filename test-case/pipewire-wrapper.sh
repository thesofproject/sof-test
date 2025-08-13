#!/bin/bash

##
## Case Name: Wrapper to run a test case given with Pipewire in setup that cannot set the environment variable. 
##    Keep this script as simple as possible and avoid additional layers of indirections when possible.
## Preconditions: 
##    Pipewire and Wireplumber are installed.
## Description:
##    This script serves as a wrapper to execute a test case script using Pipewire.
##    It expects the test case script file name (without path) as the first parameter,
##    followed by other parameters required for that test case.
## Case step:
##    1. SOF_TEST_PIPEWIRE environment variable is set to true.
##    2. The test case script is executed.
## Expected result:
##    The test case script is executed using Pipewire.

set -e

# Ensure the test case script file name is provided
if [ -z "$1" ]; then
    echo "Error: No test case script file name provided. Exiting..."
    exit 1
fi

export SOF_TEST_PIPEWIRE=true

TESTDIR=$(realpath -e "$(dirname "${BASH_SOURCE[0]}")/..")

# shellcheck disable=SC2145
[ -x "$TESTDIR/test-case/$(basename "$1")" ] && exec "$TESTDIR"/test-case/"$@"
