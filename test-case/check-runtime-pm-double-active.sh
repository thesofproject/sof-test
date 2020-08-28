#!/bin/bash

##
## Case Name: check-runtime-pm-double-active
## Preconditions:
##    N/A
## Description:
##    check the audio runtime pm status and make runtime pm status active twice
##    playback/capture -> stop -> wait till runtime pm get suspended -> playback/capture again
## Case step:
##    1. start aplay/arecord
##    2. stop aplay/arecord
##    3. keep polling on runtime pm status till 'suspended'
##    4. when 'suspended', check playback/capture again immediately
## Expect result:
##    command line check with $? without error
##    runtime pm status must be suspended
##    playback/capture must always work in right after runtime pm is suspended
##    no error in journalctl -k
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=3

OPT_OPT_lst['d']='delay'    OPT_DESC_lst['d']='max delay time for state convert'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=15

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

# param: $1 -> max delay time for dsp pm status switch, unit is second
func_check_dsp_status()
{
    # more frequent checking of the runtime pm status is required. Every loop is 100ms
    local iloop=$(expr 10 '*' "$1")
    dlogi "wait dsp power status to become suspended, starting max [100ms x $iloop times] checking"
    for i in $(seq 1 $iloop)
    do
        # Here we pass a hardcoded 0 to python script, and need to ensure
        # DSP is the first audio pci device in 'lspci', this is true unless
        # we have a third-party pci sound card installed.
        [[ $(sof-dump-status.py --dsp_status 0) == "suspended" ]] && break
        sleep 0.1
    done

    if [ $i -eq $iloop ]; then
        die "dsp is not suspended after $1s, end test"
    else
        dlogi "dsp suspended in $i try, ${i}00 msec"
    fi
}

func_opt_parse_option "$@"
tplg=${OPT_VALUE_lst['t']}
loop_count=${OPT_VALUE_lst['l']}
[[ -z $tplg ]] && dloge "Miss tplg file to run" && exit 2

[[ $(sof-dump-status.py --dsp_status 0) == "unsupported" ]] &&
    dlogi "platform doesn't support runtime pm, skip test case" && exit 2

declare -A APP_LST DEV_LST
APP_LST['playback']='aplay'
DEV_LST['playback']='/dev/zero'
APP_LST['capture']='arecord'
DEV_LST['capture']='/dev/null'

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect
func_pipeline_export $tplg "type:any"
func_lib_setup_kernel_last_timestamp

for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
do
    channel=$(func_pipeline_parse_value $idx channel)
    rate=$(func_pipeline_parse_value $idx rate)
    fmt=$(func_pipeline_parse_value $idx fmt)
    dev=$(func_pipeline_parse_value $idx dev)
    pcm=$(func_pipeline_parse_value $idx pcm)
    type=$(func_pipeline_parse_value $idx type)
    snd=$(func_pipeline_parse_value $idx snd)

    cmd="${APP_LST[$type]}"
    dummy_file="${DEV_LST[$type]}"
    [[ -z $cmd ]] && dloge "$type is not supported, $cmd, $dummy_file" && exit 2

    # discard old kernel logs
    func_lib_setup_kernel_last_timestamp
    
    for i in $(seq 1 $loop_count)
    do
        dlogi "===== Iteration $i of $loop_count for $pcm ====="
        # playback or capture device - check status
        dlogc "$cmd -D $dev -r $rate -c $channel -f $fmt $dummy_file -q"
        $cmd -D $dev -r $rate -c $channel -f $fmt $dummy_file -q &
        pid=$!

        # TODO: delay 2.5s is workaround for the SSH aplay delay issue.
        sleep 2.5

        kill -0 $pid
        if [ $? -ne 0 ]; then
            func_lib_lsof_error_dump $snd
            die "$cmd process for pcm $pcm is not alive"
        fi

        [[ -d /proc/$pid ]] && result=`sof-dump-status.py --dsp_status 0`

        dlogi "runtime status: $result"
        if [[ $result == active ]]; then
            # stop playback or capture device - check status again
            dlogc "kill process: kill -9 $pid"
            kill -9 $pid && wait $pid 2>/dev/null
            dlogi "$cmd killed"

            # check runtime pm status with maxmium timeout value, it will exit if dsp is not suspended
            func_check_dsp_status ${OPT_VALUE_lst['d']}

            result=`sof-dump-status.py --dsp_status 0`
            dlogi "runtime status: $result"
        else
            dloge "$cmd process for pcm $pcm runtime status is not active as expected"
            # stop playback or capture device otherwise no one will stop this $cmd.
            dlogc "kill process: kill -9 $pid"
            kill -9 $pid && wait $pid 2>/dev/null
            func_lib_lsof_error_dump $snd
            exit 1
        fi

        #check playback/capture again right after status change
        dlogc "Rechecking: $cmd -D $dev -r $rate -c $channel -f $fmt $dummy_file -d 1 -q"
        $cmd -D $dev -r $rate -c $channel -f $fmt $dummy_file -d 1 -q
        if [[ $? -ne 0 ]]; then
            func_lib_lsof_error_dump $snd
            die "playback/capture failed on $pcm, $dev at $i/$loop_cnt."
        fi
    done

    sof-kernel-log-check.sh "$KERNEL_LAST_TIMESTAMP" || die "Catch error in journalctl -k"
done

sof-kernel-log-check.sh "$KERNEL_LAST_TIMESTAMP"
exit $?
