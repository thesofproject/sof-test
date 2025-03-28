#!/bin/bash
# This script serves as a wrapper to execute a test case script using tinyalsa.
# It expects the test case script file name (without path) as the first parameter,
# followed by other parameters required for that test case.

set -e

# Function to check if a command is available
check_command() {
    if command -v "$1" &> /dev/null; then
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
[ -x "$TESTDIR"/test-case/"$1" ] && exec "$TESTDIR"/test-case/"$@"
