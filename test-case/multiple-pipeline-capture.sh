#!/bin/bash

##
## Case Name: Run multiple pipelines for capture
## Preconditions:
##    check-capture-10sec pass
## Description:
##    Pick up pipelines from TPLG file for max count
##    Rule:
##      a. fill pipeline need match max count
##      b. fill pipeline type order: capture > playback
##      c. if pipeline in TPLG is not enough of count, max count is pipeline count
## Case step:
##    1. Parse TPLG file to get pipeline count to decide max count is parameter or pipeline count
##    2. load capture for arecord to fill pipeline count
##    3. load playback for aplay fill pipeline count
##    4. wait for 0.5s for process already loaded
##    5. check process status & process count
##    6. wait for sleep time
##    7. check process status & process count
## Expect result:
##    all pipelines are alive and without kernel error
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['c']='count'    OPT_DESC_lst['c']='test pipeline count'
OPT_PARM_lst['c']=1         OPT_VALUE_lst['c']=4

OPT_OPT_lst['w']='wait'     OPT_DESC_lst['w']='perpare wait time by sleep'
OPT_PARM_lst['w']=1         OPT_VALUE_lst['w']=5

OPT_OPT_lst['r']='random'   OPT_DESC_lst['r']='random load pipeline'
OPT_PARM_lst['r']=0         OPT_VALUE_lst['r']=0

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=1

func_opt_parse_option "$@"
loop_cnt=${OPT_VALUE_lst['l']}
tplg=${OPT_VALUE_lst['t']}
[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

max_count=0
func_pipeline_export "$tplg" "type:any" # this line will help to get $PIPELINE_COUNT
# get the min value of TPLG:'pipeline count' with Case:'pipeline count'
[[ $PIPELINE_COUNT -gt ${OPT_VALUE_lst['c']} ]] && max_count=${OPT_VALUE_lst['c']} || max_count=$PIPELINE_COUNT
func_lib_setup_kernel_last_timestamp

# now small function define
declare -A APP_LST DEV_LST
APP_LST['playback']='aplay'
DEV_LST['playback']='/dev/zero'
APP_LST['capture']='arecord'
DEV_LST['capture']='/dev/null'

tmp_count=$max_count

# define for load pipeline
func_run_pipeline_with_type()
{
    [[ $tmp_count -le 0 ]] && return
    func_pipeline_export "$tplg" "type:$1"
    local -a idx_lst
    if [ ${OPT_VALUE_lst['r']} -eq 0 ]; then
        idx_lst=( $(seq 0 $(expr $PIPELINE_COUNT - 1)) )
    else
        # convert array to line, shuf to get random line, covert line to array
        idx_lst=( $(seq 0 $(expr $PIPELINE_COUNT - 1)|sed 's/ /\n/g'|shuf|xargs) )
    fi
    for idx in ${idx_lst[*]}
    do
        channel=$(func_pipeline_parse_value $idx channel)
        rate=$(func_pipeline_parse_value $idx rate)
        fmt=$(func_pipeline_parse_value $idx fmt)
        dev=$(func_pipeline_parse_value $idx dev)
        pcm=$(func_pipeline_parse_value $idx pcm)

        dlogi "Testing: $pcm [$dev]"

        dlogc "${APP_LST[$1]} -D $dev -c $channel -r $rate -f $fmt ${DEV_LST[$1]} -q"
        "${APP_LST[$1]}" -D $dev -c $channel -r $rate -f $fmt "${DEV_LST[$1]}" -q &

        tmp_count=$(expr $tmp_count - 1 )
        [[ $tmp_count -le 0 ]] && return
    done
}

func_error_exit()
{
    dloge "$*"
    pkill -9 aplay
    pkill -9 arecord
    exit 1
}

for i in $(seq 1 $loop_cnt)
do
    dlogi "===== Testing: (Loop: $i/$loop_cnt) ====="
    # clean up dmesg
    sudo dmesg -C

    # start capture:
    func_run_pipeline_with_type "capture"
    func_run_pipeline_with_type "playback"

    dlogi "pipeline start sleep 0.5s for device wakeup"
    sleep ${OPT_VALUE_lst['w']}

    # check all refer capture pipeline status
    # 1. check process count:
    pcount=$(pidof arecord|wc -w)
    tmp_count=$(expr $tmp_count + $pcount)
    pcount=$(pidof aplay|wc -w)
    tmp_count=$(expr $tmp_count + $pcount)
    [[ $tmp_count -ne $max_count ]] && func_error_exit "Target pipeline count: $max_count, current process count: $tmp_count"

    # 2. check arecord process status
    dlogi "checking pipeline status"
    sof-process-state.sh arecord >/dev/null
    [[ $? -eq 1 ]] && func_error_exit "Catch the abnormal process status of arecord"
    sof-process-state.sh aplay >/dev/null
    [[ $? -eq 1 ]] && func_error_exit "Catch the abnormal process status of aplay"

    dlogi "preparing sleep ${OPT_VALUE_lst['w']}"
    sleep ${OPT_VALUE_lst['w']}

    # 3. check process count again:
    tmp_count=0
    pcount=$(pidof arecord|wc -w)
    tmp_count=$(expr $tmp_count + $pcount)
    pcount=$(pidof aplay|wc -w)
    tmp_count=$(expr $tmp_count + $pcount)
    [[ $tmp_count -ne $max_count ]] && func_error_exit "Target pipeline count: $max_count, current process count: $tmp_count"

    # 4. check arecord process status
    dlogi "checking pipeline status again"
    sof-process-state.sh arecord >/dev/null
    [[ $? -eq 1 ]] && func_error_exit "Catch the abnormal process status of arecord"
    sof-process-state.sh aplay >/dev/null
    [[ $? -eq 1 ]] && func_error_exit "Catch the abnormal process status of aplay"


    # kill all arecord
    pkill -9 arecord
    pkill -9 aplay

    sof-kernel-log-check.sh 0 || die "Catch error in dmesg"
done

sof-kernel-log-check.sh $KERNEL_LAST_TIMESTAMP >/dev/null
exit $?
