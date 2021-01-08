#!/bin/bash

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2020 Intel Corporation. All rights reserved.

set -e

##
## Case Name: check-volume-levels
## Preconditions:
##    topology is nocodec with loopack in PCM0P -> PCM0C
##    aplay should work
##    arecord should work
##    PCM0C capture PGA supports -50 - +30 dB range
##    PCM0C capture PGA supports mute switch
## Description:
##    Set volume and mute switch to various values, measure
##    volume gain from the actual levels and compare to set gains.
## Case step:
##    1. Start aplay
##    2a. Capture 1st wav file
##    2b. Capture 2nd wav file
##    2c. Capture 3rd wav file
##    3. Measure volume gains
## Expect result:
##    command line check with $? without error
##

TESTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck source=case-lib/lib.sh
source "$TESTDIR/case-lib/lib.sh"

OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

func_opt_parse_option "$@"

tplg=${OPT_VALUE_lst['t']}

TPLGREADER="$TESTDIR"/tools/sof-tplgreader.py
PCM_ID=0
CAP_FORMAT="S16_LE"
CAP_RATE="48000"
VOL_P30DB=80
VOL_P10DB=60
VOL_0DB=50
VOL_M10DB=40
VOL_M20DB=30
VOL_M30DB=20
VOL_MAX=$VOL_P30DB
VOL_MIN=1
VOL_MUTE=0
VOL_NOM=$VOL_0DB
APLAY_WAV=$(mktemp --suffix=.wav)
ARECORD_WAV1=$(mktemp --suffix=.wav)
ARECORD_WAV2=$(mktemp --suffix=.wav)
ARECORD_WAV3=$(mktemp --suffix=.wav)

#
# Main test procedure
#

main () {
    # Preparations
    do_preparations
    generate_sine

    # Start sine playback
    test -f "$APLAY_WAV" || die "Error: File $APLAY_WAV does not exist"
    dlogi "Playing file $APLAY_WAV"
    timeout -k 5 120 aplay -D "$PLAY_HW" "$APLAY_WAV" & aplayPID=$!
    nap

    # Do capture tests
    run_test_1
    run_test_2
    run_test_3

    # Stop sine playback and do cleanup
    nap
    dlogi "The test procedure is now complete. Killing the aplay process $aplayPID."
    kill $aplayPID

    # Measure, delete unnecessary wav files if passed
    if measure_levels; then
	dlogi "Deleting temporary files"
	rm -f "$APLAY_WAV" "$ARECORD_WAV1" "$ARECORD_WAV2" "$ARECORD_WAV3"
    fi
}

#
# Test #1 volume and mute switch controls
#

#  0...1s channels 1-4 max gain
#  1...2s channels 1-4 different gains
#  2...3s channels 1-4 nominal gain
#  3...4s channels 1-4 muted
#  4...5s channels 1-4 nominal gain
#  5...7s channels 1-4 muted
#  7...8s channels 1-4 max gain
#  8...9s channels 1-4 muted gain
#  9..10s channels 1-4 min gain
# 10..11s channels 1-4 different gains
run_test_1 () {
    cset_max; cset_unmute; nap

    arecord_helper "$ARECORD_WAV1" "$CAP_CHANNELS" 11 & arecordPID=$!
    nap
    cset_volume_diff1 "$CAP_CHANNELS"; nap
    cset_nom; nap
    cset_mute; nap
    cset_unmute; nap
    cset_mute; nap
    cset_max; nap
    cset_unmute; nap
    cset_mutevol; nap
    cset_min; nap
    cset_volume_diff2 "$CAP_CHANNELS"

    # Wait for arecord process to complete
    dlogi "Waiting $arecordPID"
    wait $arecordPID
    dlogi "Ready."
}

#
# Test #2, check gains preservation from previous to next
#

# 0..1s channels 1-4 previous gains
# 1..2s channels 1-4 different mute switches
# 2..3s channels 1-4 all muted
run_test_2 () {
    arecord_helper "$ARECORD_WAV2" "$CAP_CHANNELS" 4 & arecordPID=$!
    nap
    cset_nom; cset_mute_diff1 "$CAP_CHANNELS"; nap
    cset_mute; nap

    dlogi "Waiting $arecordPID"
    wait $arecordPID
    dlogi "Ready."
}

#
# Test #3, test mute switch preservation from previous to next
#

# 0..1s channels 1-4 muted
# 1..2s channels 1-4  nominal gain
# 2..3s different mute switches
# 3..4s channels 1-4 nominal gain
run_test_3 () {
    arecord_helper "$ARECORD_WAV3" "$CAP_CHANNELS" 4 & arecordPID=$!
    nap
    cset_nom; nap
    cset_mute_diff2 "$CAP_CHANNELS"; nap
    cset_unmute

    dlogi "Waiting $arecordPID"
    wait $arecordPID
    dlogi "Ready."
}

#
# Helper functions
#

cset_nom () {
    dlogi "Set nominal volume"
    amixer cset name="$CAP_VOLUME" $VOL_NOM
}

cset_max () {
    dlogi "Set maximum volume"
    amixer cset name="$CAP_VOLUME" $VOL_MAX
}

cset_min () {
    dlogi "Set minimum volume"
    amixer cset name="$CAP_VOLUME" $VOL_MIN
}

cset_mutevol () {
    dlogi "Set mute via volume"
    amixer cset name="$CAP_VOLUME" $VOL_MUTE
}
cset_mute () {
    dlogi "Set mute via switch"
    amixer cset name="$CAP_SWITCH" off
}

cset_unmute () {
    dlogi "Set unmute"
    amixer cset name="$CAP_SWITCH" on
}

nap () {
    dlogi "Sleeping"
    sleep 1
}

cset_mute_diff1 () {
    dlogi "Set switch pattern 1"
    case "$1" in
	4)
	    amixer cset name="$CAP_SWITCH" off,on,on,off ;;
	2)
	    amixer cset name="$CAP_SWITCH" off,on ;;
	1)
	    amixer cset name="$CAP_SWITCH" off ;;
    esac
}

cset_mute_diff2 () {
    dlogi "Set switch pattern 2"
    case "$1" in
	4)
	    amixer cset name="$CAP_SWITCH" on,off,off,on ;;
	2)
	    amixer cset name="$CAP_SWITCH" on,off ;;
	1)
	    amixer cset name="$CAP_SWITCH" on ;;
    esac
}

cset_volume_diff1 () {
    dlogi "Set volume pattern 1"
    case "$1" in
	4)
	    amixer cset name="$CAP_VOLUME" $VOL_P10DB,$VOL_0DB,$VOL_M10DB,$VOL_M30DB ;;
	2)
	    amixer cset name="$CAP_VOLUME" $VOL_P10DB,$VOL_0DB ;;
	1)
	    amixer cset name="$CAP_VOLUME" $VOL_P10DB ;;
    esac
}

cset_volume_diff2 () {
    dlogi "Set volume pattern 2"
    case "$1" in
	4)
	    amixer cset name="$CAP_VOLUME" $VOL_M10DB,$VOL_P10DB,$VOL_0DB,$VOL_M20DB ;;
	2)
	    amixer cset name="$CAP_VOLUME" $VOL_M10DB,$VOL_P10DB ;;
	1)
	    amixer cset name="$CAP_VOLUME" $VOL_M10DB ;;
    esac
}

arecord_helper () {
    dlogi "Capturing file $1"
    timeout -k 5 30 arecord -D "$CAP_HW" -f $CAP_FORMAT -r $CAP_RATE -c "$2" -d "$3" "$1"
}

do_preparations () {

    if [[ "$tplg" != *"nocodec"* ]]; then
	# Return special value 2 with exit
	dlogi "This test is executed only with nocodec topologies. Returning Not Applicable."
	exit 2
    fi

    test -n "$(command -v octave)" || {
	dlogi "Octave not found (need octave and octave-signal packages). Returning Not Applicable."
	exit 2
    }

    # Get max. channels count to use from capture device
    # remove xargs after the trailing blank from tplgreader is fixed
    CAP_CHANNELS=$($TPLGREADER "$tplg" -f "id:$PCM_ID & type:capture" -d ch_max -v)
    CAP_HW=$($TPLGREADER "$tplg" -f "id:$PCM_ID & type:capture" -d dev -v)
    PLAY_HW=$($TPLGREADER "$tplg" -f "id:$PCM_ID & type:playback" -d dev -v)
    CAP_PGA=$($TPLGREADER "$tplg" -f "id:$PCM_ID & type:capture" -d pga -v)
    PLAY_PGA=$($TPLGREADER "$tplg" -f "id:$PCM_ID & type:playback" -d pga -v)
    export CAP_CHANNELS
    export CAP_HW
    export PLAY_HW

    dlogi "Test uses $CAP_CHANNELS channels"
    dlogi "Playback device is $PLAY_HW"
    dlogi "Playback PGA is $PLAY_PGA"
    dlogi "Capture device is $CAP_HW"
    dlogi "Capture PGA is $CAP_PGA"

    # Find amixer controls for capture, error if more than one PGA
    numpga=${#CAP_PGA[@]}
    test "$numpga" = 1 || die "Error: more than one capture PGA found."

    tmp=$(amixer controls | grep -e "$CAP_PGA.*Volume" || true )
    test -n "$tmp" || die "No control with name Volume found in $CAP_PGA"
    search="name="
    CAP_VOLUME=${tmp#*$search}
    export CAP_VOLUME
    dlogi "Capture volume control name is $CAP_VOLUME"

    tmp=$(amixer controls | grep -e "$CAP_PGA.*Switch" || true )
    test -n "$tmp" || die "No control with name Switch found in $CAP_PGA"
    CAP_SWITCH=${tmp#*$search}
    export CAP_SWITCH
    dlogi "Capture switch control name is $CAP_SWITCH"

    # Check needed controls
    amixer cget name="$CAP_VOLUME" || die "Error: failed capture volume get command"
    amixer cget name="$CAP_SWITCH" || die "Error: failed capture switch get command"

    for pga in $PLAY_PGA; do
	tmp=$(amixer controls | grep "$pga" | grep Volume)
	search="name="
	play_volume=${tmp#*$search}
	dlogi "Set $play_volume to 100%"
	amixer cset name="$play_volume" 100% || die "Error: failed play volume set command"
    done
}

generate_sine () {
    dlogi "Creating sine wave file"
    cd "$TESTDIR"/tools
    octave --silent --no-gui --eval "check_volume_levels('generate', '$APLAY_WAV')" ||
	die "Error: failed sine wave generate."
}

measure_levels () {
    dlogi "Measuring volume gains"
    cd "$TESTDIR"/tools
    octave --silent --no-gui --eval "check_volume_levels('measure', '$ARECORD_WAV1', '$ARECORD_WAV2', '$ARECORD_WAV3')" || {
	dloge "Error: Failed one or more tests in volume levels check."
	die "Please inspect files: $ARECORD_WAV1, $ARECORD_WAV2, and $ARECORD_WAV3."
    }
}

#
# Start test
#

main "$@"
