#!/bin/bash

set -e

check_device_format () {
    DEV=$1
    FMT=$2
    WAV=$(mktemp).wav
    OCTAVE_SCRIPT="noise_capture_check('${WAV}')"
    echo Testing "$DEV"
    rm -f "$WAV"
    arecord -D${DEV} $FMT -d 2 "$WAV"
    octave --silent --no-gui --eval "$OCTAVE_SCRIPT"
    status=$?
    [ $status -eq 0 ] && echo Passed.
    rm -f "$WAV"
}

check_device_format "hw:1,0" "-c 2 -r 48000 -f S16_LE"
check_device_format "hw:1,6" "-c 2 -r 48000 -f S16_LE"
check_device_format "hw:1,6" "-c 2 -r 48000 -f S32_LE"
check_device_format "hw:1,7" "-c 2 -r 16000 -f S16_LE"
check_device_format "hw:1,7" "-c 2 -r 16000 -f S32_LE"
