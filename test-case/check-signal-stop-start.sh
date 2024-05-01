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

set -e

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file, default value is env TPLG'
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['m']='mode'     OPT_DESC['m']='test mode'
OPT_HAS_ARG['m']=1         OPT_VAL['m']='playback'

OPT_NAME['i']='sleep'    OPT_DESC['i']='interval time for stop/start'
OPT_HAS_ARG['i']=1         OPT_VAL['i']=0.5

OPT_NAME['c']='count'    OPT_DESC['c']='test count of stop/start'
OPT_HAS_ARG['c']=1         OPT_VAL['c']=10

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
count=${OPT_VAL['c']}
interval=${OPT_VAL['i']}
test_mode=${OPT_VAL['m']}

start_test
logger_disabled || func_lib_start_log_collect

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

setup_kernel_check_point

func_stop_start_pipeline()
{
    local i=1
    while [ $i -le $count ]
    do
        # check aplay/arecord process state
        sof-process-state.sh "$pid" >/dev/null || {
            dloge "$cmd($pid) process is in an abnormal status"
            kill -9 "$pid"
            exit 1
        }
        dlogi "Stop/start count: $i"
        # stop the pipeline
        kill -SIGSTOP "$pid"
        sleep $interval
        # start the pipeline
        kill -SIGCONT "$pid"
        sleep $interval
        (( i++ ))
    done
}

func_pipeline_export "$tplg" "type:$test_mode"
for idx in $(seq 0 $(( "$PIPELINE_COUNT" - 1 )))
do
    channel=$(func_pipeline_parse_value "$idx" channel)
    rate=$(func_pipeline_parse_value "$idx" rate)
    fmt=$(func_pipeline_parse_value "$idx" fmt)
    dev=$(func_pipeline_parse_value "$idx" dev)
    pcm=$(func_pipeline_parse_value "$idx" pcm)
    pipeline_type=$(func_pipeline_parse_value "$idx" "type")
    snd=$(func_pipeline_parse_value "$idx" snd)

    dlogi "Testing: run stop/start test on PCM:$pcm,$pipeline_type. Interval time: $interval"
    dlogc "$cmd -D$dev -r $rate -c $channel -f $fmt $dummy_file -q &"
    $cmd -D"$dev" -r "$rate" -c "$channel" -f "$fmt" $dummy_file -q &
    pid=$!

    # If the process is terminated too early, this is error case.
    # Typical root causes of the process early termination are,
    #     1. soundcard is not enumerated
    #     2. soundcard is enumerated but the PCM device($dev) is not available
    #     3. the device is busy
    #     4. set params fails, etc
    sleep 0.5
    if [[ ! -d /proc/$pid ]]; then
        lsof "$snd"
        die "$cmd process[$pid] is terminated too early"
    fi

    # do stop/start test
    func_stop_start_pipeline

    # kill aplay/arecord process
    dlogc "kill process: kill -9 $pid"
    kill -9 "$pid"
done

sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
exit $?
