#!/bin/bash

##
## Case Name: Wrapper to run a test case given with TinyALSA
## Preconditions:
##    TinyALSA and SoX are installed.
## Description:
##    This script serves as a wrapper to execute a test case script using TinyALSA.
##    It expects the test case script file name (without path) as the first parameter,
##    followed by other parameters required for that test case.
## Case step:
##    1. SOF_ALSA_TOOL environment variable is set to TinyALSA
##    2. The test case script is executed.
## Expect result:
##    The test case script is executed using TinyALSA
##

set -e

# Ensure the test case script file name is provided
if [ -z "$1" ]; then
    echo "Error: No test case script file name provided. Exiting..."
    exit 1
fi

export SOF_ALSA_TOOL=tinyalsa

TESTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck disable=SC2145
[ -x "$TESTDIR/test-case/$(basename "$1")" ] && exec "$TESTDIR"/test-case/"$@"
