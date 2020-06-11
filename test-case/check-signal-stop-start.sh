#!/bin/bash

##
## Case Name: check-signal-stop-start
## Preconditions:
##    N/A
## Description:
##    Run aplay/arecord on each pipeline and use SIGSTOP and SIGCONT to
##    simulate keyboard inputs ctrl+z and fg.
##    kill -SIGSTOP $pid will stop the thread
##    kill -SIGCONT $pid will start the thread
## Case step:
##    1. aplay/arecord on PCM
##    2. send SIGSTOP/SIGCONT to stop/start
## Expect result:
##    no errors for aplay/arecord
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['m']='mode'     OPT_DESC_lst['m']='test mode'
OPT_PARM_lst['m']=1         OPT_VALUE_lst['m']='playback'

OPT_OPT_lst['i']='sleep'    OPT_DESC_lst['i']='interval time for stop/start'
OPT_PARM_lst['i']=1         OPT_VALUE_lst['i']=0.5

OPT_OPT_lst['c']='count'    OPT_DESC_lst['c']='test count of stop/start'
OPT_PARM_lst['c']=1         OPT_VALUE_lst['c']=10

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

func_opt_parse_option "$@"

tplg=${OPT_VALUE_lst['t']}
count=${OPT_VALUE_lst['c']}
interval=${OPT_VALUE_lst['i']}
test_mode=${OPT_VALUE_lst['m']}

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

case $test_mode in
    "playback")
        cmd=aplay
        dummy_file=/dev/zero
    ;;
    "capture")
        cmd=arecord
        dummy_file=/dev/null
    ;;
    *)
        die "Invalid test mode: $test_mode (allow value : playback, capture)"
    ;;
esac

func_lib_setup_kernel_last_line

func_stop_start_pipeline()
{
    local i=1
    while ( [ $i -le $count ] && [ "$(ps -p $pid --no-header)" ] )
    do
        # check aplay/arecord process state
        sof-process-state.sh $cmd >/dev/null
        if [ $? -ne 0 ]; then
            "$cmd process is in an abnormal status"
            kill -9 $pid && wait $pid 2>/dev/null
            exit 1
        fi
        dlogi "Stop/start count: $i"
        # stop the pipeline
        kill -SIGSTOP $pid
        sleep $interval
        # start the pipeline
        kill -SIGCONT $pid
        sleep $interval
        let i++
    done
}

func_pipeline_export $tplg "type:$test_mode"
for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
do
    channel=$(func_pipeline_parse_value $idx channel)
    rate=$(func_pipeline_parse_value $idx rate)
    fmt=$(func_pipeline_parse_value $idx fmt)
    dev=$(func_pipeline_parse_value $idx dev)
    pcm=$(func_pipeline_parse_value $idx pcm)
    pipeline_type=$(func_pipeline_parse_value $idx "type")
    snd=$(func_pipeline_parse_value $idx snd)

    dlogi "Testing: run stop/start test on PCM:$pcm,$pipeline_type. Interval time: $interval"
    dlogc "$cmd -D$dev -r $rate -c $channel -f $fmt $dummy_file -q &"
    $cmd -D$dev -r $rate -c $channel -f $fmt $dummy_file -q &
    pid=$!

    # If the process is terminated too early, this is error case.
    # Typical root causes of the process early termination are,
    #     1. soundcard is not enumerated
    #     2. soundcard is enumerated but the PCM device($dev) is not available
    #     3. the device is busy
    #     4. set params fails, etc
    sleep 0.5
    if [[ ! -d /proc/$pid ]]; then
        lsof $snd
        die "$cmd process[$pid] is terminated too early"
    fi

    # do stop/start test
    func_stop_start_pipeline
    # kill aplay/arecord process
    dlogc "kill process: kill -9 $pid"
    kill -9 $pid && wait $pid 2>/dev/null
done

sof-kernel-log-check.sh $KERNEL_LAST_LINE
exit $?
