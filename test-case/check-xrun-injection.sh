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

OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_NAME['m']='mode'     OPT_DESC['m']='test mode'
OPT_PARM_lst['m']=1         OPT_VALUE_lst['m']='playback'

OPT_NAME['c']='count' OPT_DESC['c']='test count of xrun injection'
OPT_PARM_lst['c']=1         OPT_VALUE_lst['c']=10

OPT_NAME['i']='interval'     OPT_DESC['i']='interval time of xrun injection'
OPT_PARM_lst['i']=1         OPT_VALUE_lst['i']=0.5

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

func_opt_parse_option "$@"

tplg=${OPT_VALUE_lst['t']}
test_mode=${OPT_VALUE_lst['m']}
count=${OPT_VALUE_lst['c']}
interval=${OPT_VALUE_lst['i']}

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

func_lib_setup_kernel_checkpoint
func_lib_check_sudo

case $test_mode in
    "playback")
        cmd=aplay
        test_type=p
        dummy_file=/dev/zero
    ;;
    "capture")
        cmd=arecord
        test_type=c
        dummy_file=/dev/null
    ;;
    *)
        die "Invalid test mode: $test_mode (allow value : playback, capture)"
    ;;
esac

func_xrun_injection()
{
    local i=1
    while ( [ $i -le $count ] && [ "$(ps -p $pid --no-header)" ] )
    do
        # check aplay/arecord process state
        sof-process-state.sh $pid >/dev/null
        if [[ $? -ne 0 ]]; then
            dloge "aplay/arecord process is in an abnormal status"
            kill -9 $pid && wait $pid 2>/dev/null
            exit 1
        fi
        dlogi "XRUN injection: $i"
        sudo bash -c "'echo 1 > $xrun_injection'"
        sleep $interval
	let i++
    done
}

func_pipeline_export "$tplg" "type:$test_mode"
for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
do
    channel=$(func_pipeline_parse_value $idx channel)
    rate=$(func_pipeline_parse_value $idx rate)
    fmt=$(func_pipeline_parse_value $idx fmt)
    dev=$(func_pipeline_parse_value $idx dev)
    pcm=$(func_pipeline_parse_value $idx pcm)
    id=$(func_pipeline_parse_value $idx id)
    snd=$(func_pipeline_parse_value $idx snd)
    pipeline_type=$(func_pipeline_parse_value $idx "type")
    pcm=pcm${id}${test_type}
    xrun_injection="/proc/asound/card0/$pcm/sub0/xrun_injection"

    # check xrun injection file
    [[ ! -e $xrun_injection ]] && dloge "XRUN DEBUG is not enabled in kernel, skip the test." && exit 2
    dlogi "Testing: test xrun injection on PCM:$pcm,$pipeline_type. Interval time: $interval"
    dlogc "$cmd -D$dev -r $rate -c $channel -f $fmt $dummy_file -q"
    $cmd -D$dev -r $rate -c $channel -f $fmt $dummy_file -q &
    pid=$!

    # If the process is terminated too early, this is error case.
    # Typical root causes of the process early termination are
    #     1. soundcard is not enumerated
    #     2. soundcard is enumerated but the PCM device($dev) is not available
    #     3. the device is busy
    #     4. set params fails, etc
    sleep 0.5
    if [[ ! -d /proc/$pid ]]; then
        func_lib_lsof_error_dump $snd
        die "$cmd process[$pid] is terminated too early"
    fi

    # do xrun injection
    dlogc "echo 1 > $xrun_injection"
    func_xrun_injection
    # kill aplay/arecord process
    dlogc "kill process: kill -9 $pid"
    kill -9 $pid && wait $pid 2>/dev/null
done

sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
exit $?
