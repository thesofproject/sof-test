#!/bin/bash

##
## Case Name: check-runtime-pm-status
## Preconditions:
##    N/A
## Description:
##    check the audio runtime pm status
## Case step:
##    1. start aplay
##    2. stop aplay
##    3. check the runtime pm status
## Expect result:
##    command line check with $? without error
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=3

OPT_OPT_lst['d']='delay'    OPT_DESC_lst['d']='delay time for state convert'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=6

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1


func_opt_parse_option $*
tplg=${OPT_VALUE_lst['t']}
[[ -z $tplg ]] && dloge "Miss tplg file to run" && exit 1

loop_count=${OPT_VALUE_lst['l']}

platform=$(sof-dump-status.py -p)
case $platform in
    "byt"|"cht"|"hsw"|"bdw")
        dlogi "$platform is not supported, skipping test case" && exit 2
    ;;
    *)
        dlogi "Now test power status for $platform"
    ;;
esac

runtime_status="/sys/bus/pci/devices/0000:$(lspci |awk '/[Aa]udio/ {print $1;}')/power/runtime_status"

[[ ! -f $runtime_status ]] && dloge "no runtime_status entry: $runtime_status" && exit 1

dlogc "Runtime status check: cat $runtime_status"

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect
func_pipeline_export $tplg "type:playback,capture"
func_lib_setup_kernel_last_line

for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
do
    channel=$(func_pipeline_parse_value $idx channel)
    rate=$(func_pipeline_parse_value $idx rate)
    fmt=$(func_pipeline_parse_value $idx fmt)
    dev=$(func_pipeline_parse_value $idx dev)
    pcm=$(func_pipeline_parse_value $idx pcm)
    type=$(func_pipeline_parse_value $idx type)

    if [[ $type == "playback" ]]; then
        cmd=aplay
        file=/dev/zero
    else
        cmd=arecord
        file=/dev/null
    fi

    for i in $(seq 1 $loop_count)
    do
        dlogi "Iteration $i of $loop_count for $pcm $type"
        # playback device - check status
        dlogc "$cmd -D $dev -r $rate -c $channel -f $fmt $file -q"
        $cmd -D $dev -r $rate -c $channel -f $fmt $file -q &
        pid=$!

        # TODO: delay 2.5s is workaround for the SSH aplay delay issue.
        sleep 2.5

        kill -0 $pid
        [[ $? -ne 0 ]] && dloge "$cmd process for pcm $pcm is not alive" && exit 1

        [[ -d /proc/$pid ]] && result=`cat $runtime_status`

        dlogi "runtime status: $result"
        if [[ $result == active ]]; then
            # stop playback device - check status again
            dlogc "kill process: kill -9 $pid"
            kill -9 $pid && wait $pid 2>/dev/null
            dlogi "$cmd killed"
            dlogc "sleep ${OPT_VALUE_lst['d']}"
            sleep ${OPT_VALUE_lst['d']}

            result=`cat $runtime_status`

            dlogi "runtime status: $result"
            if [[ $result != suspended ]]; then
                dloge "$cmd process for pcm $pcm runtime status is not suspended as expected"
                exit 1
            fi
        else
            dloge "$cmd process for pcm $pcm runtime status is not active as expected"
            # stop playback device otherwise no one will stop this aplay.
            dlogc "kill process: kill -9 $pid"
            kill -9 $pid && wait $pid 2>/dev/null
            exit 1
        fi
    done
done

sof-kernel-log-check.sh $KERNEL_LAST_LINE
exit $?
