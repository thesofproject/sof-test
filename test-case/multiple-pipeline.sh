#!/bin/bash

##
## Case Name: Run multiple pipelines for playback or capture
## Preconditions:
##    check-playback-10sec or check-capture-10sec pass
## Description:
##    Pick up pipelines from TPLG file for max count
##    Rule:
##      a. fill pipeline need match max count
##      b. Start filling either playback or capture depending on -f parameter
##      c. if pipeline in TPLG is not enough of count, max count is pipeline count
## Case step:
##    1. Parse TPLG file to get pipeline count to decide max count is parameter or pipeline count
##    2/3. load capture for arecord to fill pipeline count
##    2/3. load playback for aplay fill pipeline count
##    4. wait for 0.5s for process already loaded
##    5. check process status & process count
##    6. wait for sleep time
##    7. check process status & process count
## Expect result:
##    all pipelines are alive and without kernel error
##

set -e

# shellcheck source=case-lib/lib.sh
source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['c']='count'    OPT_DESC_lst['c']='test pipeline count'
OPT_PARM_lst['c']=1         OPT_VALUE_lst['c']=4

OPT_OPT_lst['f']='first'
OPT_DESC_lst['f']='Fill either playback (p) or capture (c) first'
OPT_PARM_lst['f']=1         OPT_VALUE_lst['f']='p'

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

# now small function define
declare -A APP_LST DEV_LST
APP_LST['playback']='aplay_opts'
DEV_LST['playback']='/dev/zero'
APP_LST['capture']='arecord_opts'
DEV_LST['capture']='/dev/null'

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

        "${APP_LST[$1]}" -D $dev -c $channel -r $rate -f $fmt "${DEV_LST[$1]}" -q &

        : $((tmp_count--))
        if [ "$tmp_count" -le 0 ]; then return 0; fi
    done
}

func_error_exit()
{
    dloge "$*"

    pgrep -a aplay   &&  pkill -9 aplay
    pgrep -a arecord &&  pkill -9 arecord

    exit 1
}


ps_checks()
{
    local play_count rec_count total_count
    # Extra logging
    # >&2 ps u --no-headers -C aplay -C arecord || true

    rec_count=$(ps  --no-headers -C arecord | wc -l)
    play_count=$(ps --no-headers -C aplay   | wc -l)
    total_count=$((rec_count + play_count))

    [ "$total_count" -eq "$max_count" ] ||
        func_error_exit "Target pipeline count: $max_count, current process count: $total_count"

    [ "$rec_count" = 0 ] || check_process_state arecord >/dev/null ||
        func_error_exit "Caught abnormal process status of arecord"
    [ "$play_count" = 0 ] || check_process_state aplay >/dev/null ||
        func_error_exit "Caught abnormal process status of aplay"
}


for i in $(seq 1 $loop_cnt)
do
    # set up checkpoint for each iteration
    func_lib_setup_kernel_checkpoint
    dlogi "===== Testing: (Loop: $i/$loop_cnt) ====="

    # start capture:
    f_arg=${OPT_VALUE_lst['f']}
    case "$f_arg" in
        'p')
            tmp_count=$max_count
            func_run_pipeline_with_type "playback"
            func_run_pipeline_with_type "capture"
            ;;
        'c')
            tmp_count=$max_count
            func_run_pipeline_with_type "capture"
            func_run_pipeline_with_type "playback"
            ;;
        *)
            die "Wrong -f argument $f_arg, see -h"
    esac

    dlogi "sleep ${OPT_VALUE_lst['w']}s for sound device wakeup"
    sleep ${OPT_VALUE_lst['w']}

    dlogi "checking pipeline status"
    ps_checks

    dlogi "preparing sleep ${OPT_VALUE_lst['w']}"
    sleep ${OPT_VALUE_lst['w']}

    # check processes again
    dlogi "checking pipeline status again"
    ps_checks

    dlogc 'pkill -9 aplay arecord'
    pkill -9 arecord || true
    pkill -9 aplay   || true

    # check kernel log for each iteration to catch issues
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" || die "Caught error in kernel log"
done

