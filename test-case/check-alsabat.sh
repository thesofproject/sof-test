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
OPT_HAS_ARG['f']=1             OPT_VAL['f']=821

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
frequency=${OPT_VAL['f']}
frames=${OPT_VAL['n']}

if [ "$pcm_p" = "" ]||[ "$pcm_c" = "" ];
then
	dloge "No playback or capture PCM is specified. Skip the alsabat test"
	exit 2
fi

check_locale_for_alsabat

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
        # dump amixer contents for more debugging
        amixer contents > "$LOG_ROOT"/amixer_settings.txt
        exit 1
}

wait $playPID
