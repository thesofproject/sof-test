#!/bin/bash

##
## Case Name: Wrapper to run a test case given with TinyALSA
## Preconditions:
##    TinyALSA is installed.
## Description:
##    This script serves as a wrapper to execute a test case script using TinyALSA.
##    It expects the test case script file name (without path) as the first parameter,
##    followed by other parameters required for that test case.
## Case step:
##    1. check TinyALSA and SoX are installed
##    2. SOF_ALSA_TOOL environment variable is set to TinyALSA
##    3. The test case script is executed.
## Expect result:
##    The test case script is executed using TinyALSA
##

set -e

# Function to check if a command is available
check_command() {
    if [ -x "$(command -v "$1")" ]; then
        echo "$1 is installed."
    else
        echo "$1 is not installed. Exiting..."
        exit 1
    fi
}

# Preconditions: Check if tinyalsa executables are present on the DUT
check_command "sox"
check_command "tinycap"
check_command "tinyplay"

# Ensure the test case script file name is provided
if [ -z "$1" ]; then
    echo "Error: No test case script file name provided. Exiting..."
    exit 1
fi

export SOF_ALSA_TOOL=tinyalsa

TESTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck disable=SC2145
[ -x "$TESTDIR/test-case/$(basename "$1")" ] && exec "$TESTDIR"/test-case/"$@"
