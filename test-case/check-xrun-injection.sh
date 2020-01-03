#!/bin/bash

##
## Case Name: check-xrun-injection
## Preconditions:
##    Need to enable CONFIG_SND_PCM_XRUN_DEBUG in kenrel config
## Description:
##    check xrun injection during playback/capture
##    default duration is 10s
##    default interval time of xrun injection is 0.5s
## Case step:
##    1. Parse TPLG file to get pipeline
##    2. Specify the audio parameters
##    3. Run aplay or arecord on each pipeline with parameters
##    4. do xrun injection during playback or capture
## Expect result:
##    The return value of aplay/arecord should be 0
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['d']='duration' OPT_DESC_lst['d']='aplay/arecord duration in second'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=10

OPT_OPT_lst['i']='interval'     OPT_DESC_lst['i']='interval time of xrun injection'
OPT_PARM_lst['i']=1         OPT_VALUE_lst['i']=0.5

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

func_opt_parse_option $*

tplg=${OPT_VALUE_lst['t']}
duration=${OPT_VALUE_lst['d']}
interval=${OPT_VALUE_lst['i']}

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

func_lib_setup_kernel_last_line
func_lib_check_sudo
func_pipeline_export $tplg "type:playback,capture,both"

declare -A CMD FILE
CMD['playback,both']='aplay'
FILE['playback,both']='/dev/zero'
CMD['capture,both']='arecord'
FILE['capture,both']='/dev/null'

func_xrun_injection()
{
    count=1
    while(true)
    do
        ps -ef |grep "$pid" |grep -v grep
        if [ $? -eq 0 ]; then
            dlogi "XRUN injection: $count"
            sudo bash -c "'echo 1 > $xrun_injection'"
            sleep $interval
            let count++
        else
            break # aplay/arecord is finished, stop xrun injection
        fi
    done
}

func_test_pipeline_with_type()
{
    func_pipeline_export $tplg "type:$1"
    for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
    do
        channel=$(func_pipeline_parse_value $idx channel)
        rate=$(func_pipeline_parse_value $idx rate)
        fmt=$(func_pipeline_parse_value $idx fmt)
        dev=$(func_pipeline_parse_value $idx dev)
        pcm=$(func_pipeline_parse_value $idx pcm)
        id=$(func_pipeline_parse_value $idx id)
        pipeline_type=$(func_pipeline_parse_value $idx "type")
        pcm=pcm${id}${2}
        xrun_injection="/proc/asound/card0/$pcm/sub0/xrun_injection"

        # check xrun injection file
        [[ ! -e $xrun_injection ]] && dloge "XRUN DEBUG is not enabled in kernel, skip the test." && exit 2
        dlogi "Testing: test xrun injection on PCM:$pcm,$pipeline_type. Interval time: $interval"
        dlogc "${CMD[$1]}" -D$dev -r $rate -c $channel -f $fmt -d $duration "${FILE[$1]}" -q
        "${CMD[$1]}" -D$dev -r $rate -c $channel -f $fmt -d $duration "${FILE[$1]}" -q &
        pid=$!
        # do xrun injection
        dlogc "echo 1 > $xrun_injection"
        func_xrun_injection
        # check aplay/arecord return value
        wait $pid
        if [ $? != 0 ]; then
            dloge "$pipeline_type on $pcm failed."
            exit 1
        fi
    done
}

func_test_pipeline_with_type "playback,both" "p"
func_test_pipeline_with_type "capture,both" "c"

sof-kernel-log-check.sh $KERNEL_LAST_LINE
exit $?
