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

libdir=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source=case-lib/lib.sh
source "$libdir"/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'         OPT_DESC_lst['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_PARM_lst['t']=1             OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['p']='pcm_p'     	OPT_DESC_lst['p']='pcm for playback. Example: hw:0,0'
OPT_PARM_lst['p']=1          	OPT_VALUE_lst['p']=''

OPT_OPT_lst['c']='pcm_c'      	OPT_DESC_lst['c']='pcm for capture. Example: hw:1,0'
OPT_PARM_lst['c']=1             OPT_VALUE_lst['c']=''

OPT_OPT_lst['f']='frequency'    OPT_DESC_lst['f']='target frequency'
OPT_PARM_lst['f']=1             OPT_VALUE_lst['f']=997

OPT_OPT_lst['n']='frames'       OPT_DESC_lst['n']='test frames'
OPT_PARM_lst['n']=1             OPT_VALUE_lst['n']=240000

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

func_opt_parse_option "$@"

tplg=${OPT_VALUE_lst['t']}
pcm_p=${OPT_VALUE_lst['p']}
pcm_c=${OPT_VALUE_lst['c']}
frequency=${OPT_VALUE_lst['f']}
frames=${OPT_VALUE_lst['n']}

if [ "$pcm_p" = "" ]||[ "$pcm_c" = "" ];
then
	dloge "No playback or capture PCM is specified. Skip the alsabat test"
	exit 2
fi

pcmid_p=${pcm_p:-1}

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

func_pipeline_export "$tplg" "type:playback & id:$pcmid_p"

# parser the parameters of the specified playback pipeline
channel=$(func_pipeline_parse_value 0 ch_max)
rate=$(func_pipeline_parse_value 0 rate)
fmts=$(func_pipeline_parse_value 0 fmts)

# check the PCMs before alsabat test
dlogi "check the PCMs before alsabat test"
[[ $(aplay -Dplug$pcm_p -d 1 /dev/zero -q) ]] && die "Failed to play on PCM: $pcm_p"
[[ $(arecord -Dplug$pcm_c -d 1 /dev/null -q) ]] && die "Failed to capture on PCM: $pcm_c"

# alsabat test
for format in $fmts
    do
        if [ "$format" == "S24_LE" ]; then
            dlogi "S24_LE is not supported, skip to test this format"
            continue
        fi

        dlogc "alsabat -P $pcm_p --standalone -n $frames -F $frequency -c $channel -r $rate -f $format"
        alsabat -P "$pcm_p" --standalone -n "$frames" -F "$frequency" -c "$channel" -r "$rate" \
		-f "$format" & alsabatPID=$!
        # playback may have low latency, add one second delay to aviod recording zero at beginning.
        sleep 1

        if func_nocodec_mode; then
            format_c=$format
            channel_c=$channel
        else
            # USB sound card only supports 1 channel S16_LE format.
            format_c=S16_LE
            channel_c=1
        fi

        dlogc "alsabat -C $pcm_c -F $frequency -f $format_c -c $channel_c -r $rate"
        alsabat -C "$pcm_c" -F "$frequency" -f "$format_c" -c "$channel_c" -r "$rate" || {
            func_upload_wav_file "/tmp" "bat.wav.*" || true
            exit 1
        }
        # check the alsabat -P exit code
        if ! wait $alsabatPID; then
            die "alsabat -P failure"
        fi
done

exit 0
