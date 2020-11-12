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

OPT_OPT_lst['p']='pcm_p'     	OPT_DESC_lst['p']='pcm for playback. Example: hw:0,0'
OPT_PARM_lst['p']=1          	OPT_VALUE_lst['p']=''

OPT_OPT_lst['c']='pcm_c'      	OPT_DESC_lst['c']='pcm for capture. Example: hw:1,0'
OPT_PARM_lst['c']=1             OPT_VALUE_lst['c']=''

OPT_OPT_lst['f']='frequency'    OPT_DESC_lst['f']='target frequency'
OPT_PARM_lst['f']=1             OPT_VALUE_lst['f']=997

OPT_OPT_lst['n']='frames'     OPT_DESC_lst['n']='test frames'
OPT_PARM_lst['n']=1             OPT_VALUE_lst['n']=240000

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

func_opt_parse_option "$@"

pcm_p=${OPT_VALUE_lst['p']}
pcm_c=${OPT_VALUE_lst['c']}
frequency=${OPT_VALUE_lst['f']}
frames=${OPT_VALUE_lst['n']}

if [ "$pcm_p" = "" ]||[ "$pcm_c" = "" ];
then
	dloge "No playback or capture PCM is specified. Skip the alsabat test"
	exit 2
fi

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

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
[[ $(aplay -Dplug$pcm_p -d 1 /dev/zero -q) ]] && die "Failed to play on PCM: $pcm_p"
[[ $(arecord -Dplug$pcm_c -d 1 /dev/null -q) ]] && die "Failed to capture on PCM: $pcm_c"

# alsabat test
# different PCMs may support different audio formats(like samplerate, channel-counting, etc.).
# use plughw to do the audio format conversions. So we don't need to specify them for each PCM.
dlogc "alsabat -Pplug$pcm_p --standalone -n $frames -F $frequency"
alsabat -Pplug$pcm_p --standalone -n $frames -F $frequency & playPID=$!

# playback may have low latency, add one second delay to aviod recording zero at beginning.
sleep 1
dlogc "alsabat -Cplug$pcm_c -F $frequency"
alsabat -Cplug$pcm_c -F $frequency || {
# upload failed wav file
	__upload_wav_file
	exit 1
}

wait $playPID
