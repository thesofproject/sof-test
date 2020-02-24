#!/bin/bash

##
## Case Name: check-pulseaudio
## Preconditions:
##    PulseAudio should be enabled
##    UCM files should be available
##    Basic playback and capture should work
##
## Description:
##    Query number of sinks and sources and set one to default.
##    playback with paplay and capture with parecord respectively will
##    be used. And will check for return value.
##
## Case step:
##    For playback,
##    1. Query sinks for playback
##    2. Set default sink and paplay
##
##    For capture,
##    1. Query sources for capture
##    2. Set default source and parecord
##
## Expect result:
##    no error happen for paplay and parecord
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['m']='mode'     OPT_DESC_lst['m']='test mode'
OPT_PARM_lst['m']=1         OPT_VALUE_lst['m']='playback'

OPT_OPT_lst['d']='duration' OPT_DESC_lst['d']='aplay or arecord duration in second'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=7

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=3

OPT_OPT_lst['f']='file'     OPT_DESC_lst['f']='file name'
OPT_PARM_lst['f']=1         OPT_VALUE_lst['f']=''

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

#function : func_parse_pulseaudio_sink_source
#    get pulseaudio sources or sinks
#    input param1 : test mode, playback or capture
func_parse_pulseaudio_sink_source()
{
    local _mode=$1
    case $_mode in
        "playback")
            declare -ga pulse_device_list=$(pactl list short sinks | grep -v "usb" | cut -c 1)
        ;;
        "capture")
            declare -ga pulse_device_list=$(pactl list short sources | grep source | grep -v "usb" | cut -c 1)
        ;;
    esac

    dlogi "input $_mode, ${pulse_device_list[*]}"
}

func_opt_parse_option $*

dlogi "PulseAudio should be enabled before starting the test, ${PULSECMD_LST[*]}"
func_lib_restore_pulseaudio

tplg=${OPT_VALUE_lst['t']}
test_mode=${OPT_VALUE_lst['m']}
duration=${OPT_VALUE_lst['d']}
loop_cnt=${OPT_VALUE_lst['l']}
file_name=${OPT_VALUE_lst['f']}
case $test_mode in
    "playback")
        cmd=paplay
        [[ -z $file_name ]] && dloge "PulseAudio need input wave file" && exit 1

        [[ ! -f $file_name ]] && dloge "input wave file not available $file_name" && exit 2
        audio_filename=$file_name
        ;;
    "capture")
        cmd=parecord
        if [[ -z $file_name ]]; then
            dlogw "PulseAudio set output file to /tmp/patmp.wav" && audio_filename="/tmp/patmp.wav"
        else
            audio_filename=$file_name
        fi
        ;;
    *)
        dloge "Invalid test mode: $test_mode (allow value : playback, capture)"
        exit 1
        ;;
esac

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

#func_pipeline_export $tplg "type:$test_mode"
func_lib_setup_kernel_last_line

func_parse_pulseaudio_sink_source $test_mode

for i in $(seq 1 $loop_cnt)
do
    dlogi "Testing: (Loop: $i/$loop_cnt)"
    for idx in $pulse_device_list
    do

        if [ $test_mode == "playback" ]; then
            dlogi "playback: pacmd set-default-sink $idx"
            pacmd set-default-sink $idx
        else
            dlogi "capture: pacmd set-default-source $idx"
            pacmd set-default-source $idx
        fi
        ret=$?
        if [ $ret -ne 0 ]; then
            dloge "pacmd for $test_mode failed"
            exit $ret
        fi

        # background PulseAudio playback or capture
        $cmd $audio_filename &
        sleep 1

        dlogi "checking paluseaudio $cmd process status"
        sof-process-state.sh $cmd >/dev/null
        [[ $? -eq 1 ]] && func_error_exit "Catch the abnormal process status of $cmd"

        sleep $duration

        dlogi "checking paluseaudio cmd status after sleep $duration"
        sof-process-state.sh $cmd >/dev/null
        [[ $? -eq 1 ]] && func_error_exit "Catch the abnormal process status of $cmd"
        pkill -9 $cmd

        #for playback, no more checking
        #for capture, file size check
        if [ $test_mode == "capture" ]; then
            if [ ! -s $audio_file ]; then
                dloge "captured file is zero or not exist!"
                exit 1
            fi
	    # Wav RIFF header, 'RIFWAVEfmt'
            #head -c 20 $audio_file
        fi

        # sof-kernel-log-check script parameter number is 0/Non-Number will force check from dmesg
        sof-kernel-log-check.sh 0
        [[ $? -ne 0 ]] && dloge "Catch dmesg error" && exit 1
    done

done #end of loop_cnt

sof-kernel-log-check.sh $KERNEL_LAST_LINE
exit $?
