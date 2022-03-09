#!/bin/bash

##
## Case Name: multiple-pipeline
## Preconditions:
##    playback and capture features work well, they can be checked with
##    check-playback.sh and check-capture.sh
## Description:
##    Run multiple pipelines in parallel
##    Rule:
##      1. playback first mode: playback pipelines will be started first, if playback
##         pipeline count is less than requested pipeline count defined by -c option,
##         capture pipelines will be started to ensure requested number of pipelines are
##         running in parallel.
##      2. capture first mode: same with playback mode, but capture pipelines will be
##         started first.
##      3. all pipelines mode: run all pipelines in parallel by
##          a. use option '-f a' OR
##          b. specify a very big requested pipeline count to -c option
## Case step:
##    1. acquire pipeline count that will be running in parallel
##    2. start playback or capture pipelines
##        a. Playback First Mode: start playback pipeline(s), if the requested pipeline count
##        is not satisfied, start capture pipeline(s)
##        b. Capture First Mode: start capture pipeline(s), if the requested pipeline count is
##        not satisfied, start playback pipeline(s)
##    3. wait pipeline process(es) to be started and running
##    5. check process status & process count
##    6. running pipelines in parallel for a period of time defined by -w option
##    7. re-check process status & process count
## Expect result:
##    all pipelines are alive and no kernel and SOF errors detected
##

set -e

TESTDIR="$(dirname "${BASH_SOURCE[0]}")"/..

# shellcheck source=case-lib/lib.sh
source "${TESTDIR}"/case-lib/lib.sh

OPT_NAME['t']='tplg'     OPT_DESC['t']='Topology path, default to environment variable: TPLG'
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['c']='count'    OPT_DESC['c']='test pipeline count'
OPT_HAS_ARG['c']=1         OPT_VAL['c']=4

OPT_NAME['f']='first'
OPT_DESC['f']='Fill either playback (p) or capture (c) first or any (a) for all pipelines'
OPT_HAS_ARG['f']=1         OPT_VAL['f']='p'

OPT_NAME['w']='wait'     OPT_DESC['w']='duration of one (sub)test iteration'
OPT_HAS_ARG['w']=1         OPT_VAL['w']=5

OPT_NAME['r']='random'   OPT_DESC['r']='random load pipeline'
OPT_HAS_ARG['r']=0         OPT_VAL['r']=0

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=1

func_opt_parse_option "$@"
loop_cnt=${OPT_VAL['l']}
tplg=${OPT_VAL['t']}
f_arg=${OPT_VAL['f']}
logger_disabled || func_lib_start_log_collect

# skip the Echo Reference pipeline
MULTI_PIPELINE_FILTER='~pcm:Amplifier Reference'
max_count=0
# this line will help to get $PIPELINE_COUNT
func_pipeline_export "$tplg" "type:any & ${MULTI_PIPELINE_FILTER}"
# acquire pipeline count that will run in parallel, if the number of pipeline
# in topology is less than the required pipeline count, all pipeline will be started.
[[ $PIPELINE_COUNT -gt ${OPT_VAL['c']} ]] && max_count=${OPT_VAL['c']} || max_count=$PIPELINE_COUNT
# overide max_count if user want to run all pipelines in parallel
[ "$f_arg" != "a" ] || max_count=$PIPELINE_COUNT

# now small function define
declare -A APP_LST DEV_LST
APP_LST['playback']='aplay_opts'
DEV_LST['playback']='/dev/zero'
APP_LST['capture']='arecord_opts'
DEV_LST['capture']='/dev/null'

# define for load pipeline
# args: $1: playback or capture
#       $2: optional filter
func_run_pipeline_with_type()
{
    local direction="$1"
    local opt_filter
    [ -n "$2" ] && opt_filter="& $2"
    [[ $tmp_count -le 0 ]] && return
    func_pipeline_export "$tplg" "type:$direction $opt_filter"
    local -a idx_lst
    if [ ${OPT_VAL['r']} -eq 0 ]; then
        idx_lst=("$(seq 0 $((PIPELINE_COUNT - 1)))")
    else
        # convert array to line, shuf to get random line, covert line to array
        idx_lst=("$(seq 0 $((PIPELINE_COUNT - 1)) | sed 's/ /\n/g' | shuf | xargs)")
    fi
    for idx in ${idx_lst[*]}
    do
        channel=$(func_pipeline_parse_value "$idx" channel)
        rate=$(func_pipeline_parse_value "$idx" rate)
        fmt=$(func_pipeline_parse_value "$idx" fmt)
        dev=$(func_pipeline_parse_value "$idx" dev)
        pcm=$(func_pipeline_parse_value "$idx" pcm)

        dlogi "Testing: $pcm [$dev]"

        "${APP_LST[$direction]}" -D "$dev" -c "$channel" -r "$rate" -f "$fmt" "${DEV_LST[$direction]}" -q &

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
        func_error_exit "Running process count is $total_count, but $max_count is expected"

    [ "$rec_count" = 0 ] || sof-process-state.sh arecord >/dev/null ||
        func_error_exit "Caught abnormal process status of arecord"
    [ "$play_count" = 0 ] || sof-process-state.sh aplay >/dev/null ||
        func_error_exit "Caught abnormal process status of aplay"
}

main()
{
    local platf; platf=$("${TESTDIR}"/tools/sof-dump-status.py --platform)
    if [ "$platf" = bdw ] && [ "$f_arg" != 'p' ] && ! is_zephyr; then
        skip_test \
            "multi-capture disabled on BDW https://github.com/thesofproject/sof/issues/3170"
    fi
}

main "$@"

# TODO: move this to main() https://github.com/thesofproject/sof-test/issues/740
for i in $(seq 1 $loop_cnt)
do
    # set up checkpoint for each iteration
    setup_kernel_check_point
    dlogi "===== Testing: (Loop: $i/$loop_cnt) ====="

    # start playback or capture:
    case "$f_arg" in
        'p' | 'a')
            tmp_count=$max_count
            func_run_pipeline_with_type "playback"
            func_run_pipeline_with_type "capture" "${MULTI_PIPELINE_FILTER}"
            ;;
        'c')
            tmp_count=$max_count
            func_run_pipeline_with_type "capture" "${MULTI_PIPELINE_FILTER}"
            func_run_pipeline_with_type "playback"
            ;;
        *)
            die "Wrong -f argument $f_arg, see -h"
    esac

    # Give the aplay_opts and arecord_opts subshells some time to start
    # their aplay processes.
    dlogi "wait 0.5s for aplay_opts()"
    sleep 0.5
    dlogi "checking pipeline status"
    ps_checks

    dlogi "Letting playback/capture run for ${OPT_VAL['w']}s"
    sleep ${OPT_VAL['w']}

    # check processes again
    dlogi "checking pipeline status again"
    ps_checks

    dlogc 'pkill -9 aplay arecord'
    pkill -9 arecord || true
    pkill -9 aplay   || true
    sleep 1 # try not to pollute the next iteration

    # check kernel log for each iteration to catch issues
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" || die "Caught error in kernel log"
done

