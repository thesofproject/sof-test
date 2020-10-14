#!/bin/bash

##
## Case Name: check alsabat
## Preconditions:
##    This test case requires physical loopback between playback and capture.
##    playback <=====>  capture
##    nocodec : no need to use hw loopback cable, It support DSP loopback by quirk
## Description:
##    run alsabat test on the specified pipelines
## Case step:
##    1. Specify the pcm IDs for playback and catpure
##    3. run alsabat test
## Expect result:
##    The return value of alsabat is 0
##

# remove the existing alsabat wav files
rm -f /tmp/bat.wav.*

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['p']='pcm_p'     	OPT_DESC['p']='pcm for playback. Example: hw:0,0'
OPT_HAS_ARG['p']=1          	OPT_VAL['p']=''

OPT_NAME['C']='channel_c'       OPT_DESC['C']='channel number for capture.'
OPT_HAS_ARG['C']=1             OPT_VAL['C']='1'

OPT_NAME['r']='rate'            OPT_DESC['r']='sample rate'
OPT_HAS_ARG['r']=1             OPT_VAL['r']=48000

OPT_NAME['c']='pcm_c'      	OPT_DESC['c']='pcm for capture. Example: hw:1,0'
OPT_HAS_ARG['c']=1             OPT_VAL['c']=''

OPT_NAME['f']='frequency'       OPT_DESC['f']='target frequency'
OPT_HAS_ARG['f']=1             OPT_VAL['f']=997

OPT_NAME['n']='frames'          OPT_DESC['n']='test frames'
OPT_HAS_ARG['n']=1             OPT_VAL['n']=240000

OPT_NAME['s']='sof-logger'      OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

OPT_NAME['t']='tplg'            OPT_DESC['f']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1             OPT_VAL['f']="$TPLG"

TESTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TPLGREADER="$TESTDIR"/tools/sof-tplgreader.py

func_opt_parse_option "$@"

pcm_p=${OPT_VAL['p']}
pcm_c=${OPT_VAL['c']}
rate=${OPT_VAL['r']}
channel_c=${OPT_VAL['C']}
frequency=${OPT_VAL['f']}
frames=${OPT_VAL['n']}
tplg=${OPT_VAL['t']}

if [ "$pcm_p" = "" ]||[ "$pcm_c" = "" ];
then
	dloge "No playback or capture PCM is specified. Skip the alsabat test"
	exit 2
fi

[[ ${OPT_VAL['s']} -eq 1 ]] && func_lib_start_log_collect

function __upload_wav_file
{
    # upload the alsabat wav file
    for file in /tmp/bat.wav.*
    do
	# alsabat has a bug where it creates an empty record in playback
	# mode
	if test -s "$file"; then
	    cp "$file" "$LOG_ROOT/"
	fi
    done
}

set_pga_to_unity_gain()
{
    tmp=$(amixer controls | grep "$1" | grep Volume)
    search="name="
    cname=${tmp#*$search}

    # Get volume min and step to compute value for cset
    # for 0 dB gain. The amixer line looks like
    # "| dBscale-min=-50.00dB,step=1.00dB,mute=1"
    scale=$(amixer cget name="$cname" | grep "dBscale" || true)
    search="dBscale-min="
    tmp=${scale#*$search}
    min_db="${tmp%%dB*}"
    search="step="
    tmp=${scale#*$search}
    step_db="${tmp%%dB*}"

    # Get multiplied by 100 values by removing decimal dot
    min_x100="${min_db//.}"
    step_x100="${step_db//.}"
    val=$(printf %d "$(((-min_x100) / step_x100))")

    # Apply the computed value for requested gain
    amixer cset name="$cname" "$val"
}

set_pgas_list_to_unity_gain()
{
    for pga in "$@"; do
	dlogi "Set $pga"
	set_pga_to_unity_gain "$pga"
    done
}

get_snd_base()
{
    # Converts e.g. string hw:1,0 to /dev/snd/pcmC1D0
    # the p or c for playback or capture is appended
    # in the calling function.
    tmp=${1#*"hw:"}
    ncard="${tmp%%,*}"
    ndevice="${tmp#*,}"
    echo "/dev/snd/pcmC${ncard}D${ndevice}"
}

get_play_snd()
{
    tmp=$(get_snd_base "$1")
    echo "${tmp}"p
}

get_capture_snd()
{
    tmp=$(get_snd_base "$1")
    echo "${tmp}"c
}

# check the PCMs before alsabat test
dlogi "check the PCMs before alsabat test"
aplay   -Dplug$pcm_p -d 1 /dev/zero -q || die "Failed to play on PCM: $pcm_p"
arecord -Dplug$pcm_c -d 1 /dev/null -q || die "Failed to capture on PCM: $pcm_c"

# Set PGAs for PCMs to 0 dB value
test -n "$(command -v "$TPLGREADER")" ||
    die "Command $TPLGREADER is not available."

test -n "$tplg" || die "Use -t or set environment variable TPLG to current topology"
tplg_full_path=$(func_lib_get_tplg_path "$tplg")
dlogi "Getting playback PGA information"
play_snd=$(get_play_snd "$pcm_p")
PLAY_PGAS=$($TPLGREADER "$tplg_full_path" -f "snd:$play_snd" -d pga -v)
set_pgas_list_to_unity_gain $PLAY_PGAS
dlogi "Getting capture PGA information"
cap_snd=$(get_capture_snd "$pcm_c")
CAP_PGAS=$($TPLGREADER "$tplg_full_path" -f "snd:$cap_snd" -d pga -v)
set_pgas_list_to_unity_gain $CAP_PGAS

# alsabat test
# hardcode the channel number of playback to 2, as sof doesnot support mono wav.
dlogc "alsabat -P$pcm_p --standalone -n $frames -r $rate -c 2 -F $frequency"
alsabat -P$pcm_p --standalone -n $frames -c 2 -r $rate -F $frequency & playPID=$!

# playback may have low latency, add one second delay to aviod recording zero at beginning.
sleep 1

# We use different USB sound cards in CI, part of them only support 1 channel for capture,
# so make the channel as an option and config it in alsabat-playback.csv
dlogc "alsabat -C$pcm_c -c $channel_c -r $rate -F $frequency"
alsabat -C$pcm_c -c $channel_c -r $rate -F $frequency || {
        # upload failed wav file
        __upload_wav_file
        exit 1
}

wait $playPID
