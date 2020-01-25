#!/bin/bash

##
## Case Name: simultaneous-playback-capture
## Preconditions:
##    N/A
## Description:
##    simultaneous running of aplay and arecord on "both" pipelines
## Case step:
##    1. Parse TPLG file to get pipeline with type "both"
##    2. Run aplay and arecord
##    3. Check for aplay and arecord process existence
##    4. Sleep for given time period
##    5. Check for aplay and arecord process existence
##    6. Kill aplay & arecord processes
## Expect result:
##    aplay and arecord processes survive for entirety of test until killed
##    check kernel log and find no errors
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['w']='wait'     OPT_DESC_lst['w']='sleep for wait duration'
OPT_PARM_lst['w']=1         OPT_VALUE_lst['w']=5

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=1

func_opt_parse_option $*
tplg=${OPT_VALUE_lst['t']}
wait_time=${OPT_VALUE_lst['w']}
loop_cnt=${OPT_VALUE_lst['l']}

func_pipeline_export $tplg "type:both"
[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect
func_lib_setup_kernel_last_line

func_error_exit()
{
    dloge "$*"
    kill -9 $aplay_pid && wait $aplay_pid 2>/dev/null
    kill -9 $arecord_pid && wait $arecord_pid 2>/dev/null
    exit 1
}

for i in $(seq 1 $loop_cnt)
do
    dlogi "Testing: (Loop: $i/$loop_cnt)"
    # clean up dmesg
    sudo dmesg -C
    for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
    do
        channel=$(func_pipeline_parse_value $idx channel)
        rate=$(func_pipeline_parse_value $idx rate)
        fmt=$(func_pipeline_parse_value $idx fmt)
        dev=$(func_pipeline_parse_value $idx dev)

        dlogc "aplay -D $dev -c $channel -r $rate -f $fmt /dev/zero -q &"
        aplay -D $dev -c $channel -r $rate -f $fmt /dev/zero -q &
        aplay_pid=$!

        dlogc "arecord -D $dev -c $channel -r $rate -f $fmt /dev/null -q &"
        arecord -D $dev -c $channel -r $rate -f $fmt /dev/null -q &
        arecord_pid=$!

        dlogi "Preparing to sleep for $wait_time"
        sleep $wait_time

        # aplay/arecord processes should be persistent for sleep duration.
        dlogi "check pipeline after ${wait_time}s"
        kill -0 $aplay_pid
        [[ $? -ne 0 ]] && func_error_exit "Error in aplay process after sleep."

        kill -0 $arecord_pid
        [[ $? -ne 0 ]] && func_error_exit "Error in arecord process after sleep."

        # kill all live processes, successful end of test
        dlogc "killing all pipelines"
        kill -9 $aplay_pid && wait $aplay_pid 2>/dev/null
        kill -9 $arecord_pid && wait $arecord_pid 2>/dev/null

    done
    sof-kernel-log-check.sh 0
    [[ $? -ne 0 ]] && dloge "Catch dmesg error" && exit 1
done

sof-kernel-log-check.sh $KERNEL_LAST_LINE > /dev/null
exit $?
