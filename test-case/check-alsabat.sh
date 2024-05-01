#!/bin/bash

##
## Case Name: check alsabat
##
## Preconditions:
##    This test case requires physical loopback between playback and capture.
##    playback <=====>  capture
##    nocodec : no need to use hw loopback cable, It support DSP loopback by quirk
##
## Description:
##    Run two alsabat instances concurrently, one on each specified PCM: playback
##    and capture.
##
##    Warning: as of January 2024, "man alsabat" is incomplete and
##    documents only the "single instance" mode where a single alsabat
##    process performs both playback and capture.
##
## Case step:
##    1. Specify the pcm IDs for playback and catpure
##    3. run alsabat test
##
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

OPT_NAME['N']='channel_p'       OPT_DESC['N']='channel number for playback.'
OPT_HAS_ARG['N']=1             OPT_VAL['N']='2'

OPT_NAME['r']='rate'            OPT_DESC['r']='sample rate'
OPT_HAS_ARG['r']=1             OPT_VAL['r']=48000

OPT_NAME['c']='pcm_c'      	OPT_DESC['c']='pcm for capture. Example: hw:1,0'
OPT_HAS_ARG['c']=1             OPT_VAL['c']=''

OPT_NAME['f']='format'       OPT_DESC['f']='target format'
OPT_HAS_ARG['f']=1             OPT_VAL['f']="S16_LE"

OPT_NAME['F']='frequency'       OPT_DESC['F']='target frequency'
OPT_HAS_ARG['F']=1             OPT_VAL['F']=821

OPT_NAME['k']='sigmak'		OPT_DESC['k']='sigma k value'
OPT_HAS_ARG['k']=1             OPT_VAL['k']=2.1

OPT_NAME['n']='frames'          OPT_DESC['n']='test frames'
OPT_HAS_ARG['n']=1             OPT_VAL['n']=240000

OPT_NAME['s']='sof-logger'      OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

func_opt_parse_option "$@"
setup_kernel_check_point

pcm_p=${OPT_VAL['p']}
pcm_c=${OPT_VAL['c']}
rate=${OPT_VAL['r']}
channel_c=${OPT_VAL['C']}
channel_p=${OPT_VAL['N']}
format=${OPT_VAL['f']}
frequency=${OPT_VAL['F']}
sigmak=${OPT_VAL['k']}
frames=${OPT_VAL['n']}

start_test

if [ "$pcm_p" = "" ]||[ "$pcm_c" = "" ];
then
	dloge "No playback or capture PCM is specified. Skip the alsabat test"
	exit 2
fi

check_locale_for_alsabat

# reset sof volume to 0dB
reset_sof_volume

# If MODEL is defined, set proper gain for the platform
if [ -z "$MODEL" ]; then
    # treat as warning only
    dlogw "NO MODEL is defined. Please define MODEL to run alsa_settings/MODEL.sh"
else
    #dlogi "apply alsa settings for alsa_settings/MODEL.sh"
    set_alsa_settings "$MODEL"
fi

logger_disabled || func_lib_start_log_collect

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

# check the PCMs before alsabat test
dlogi "check the PCMs before alsabat test"
aplay   -Dplug$pcm_p -d 1 /dev/zero -q || die "Failed to play on PCM: $pcm_p"
arecord -Dplug$pcm_c -d 1 /dev/null -q || die "Failed to capture on PCM: $pcm_c"

# alsabat test
# BT offload PCMs also support mono playback.
dlogc "alsabat -P$pcm_p --standalone -n $frames -r $rate -c $channel_p -f $format -F $frequency -k $sigmak"
alsabat -P$pcm_p --standalone -n $frames -c $channel_p -r $rate -f $format -F $frequency -k $sigmak & playPID=$!

# playback may have low latency, add one second delay to aviod recording zero at beginning.
sleep 1

# We use different USB sound cards in CI, part of them only support 1 channel for capture,
# so make the channel as an option and config it in alsabat-playback.csv
dlogc "alsabat -C$pcm_c -c $channel_c -r $rate -f $format -F $frequency -k $sigmak"
alsabat -C$pcm_c -c $channel_c -r $rate -f $format -F $frequency -k $sigmak || {
        # upload failed wav file
        __upload_wav_file
        # dump amixer contents for more debugging
        amixer contents > "$LOG_ROOT"/amixer_settings.txt
        exit 1
}

wait $playPID
