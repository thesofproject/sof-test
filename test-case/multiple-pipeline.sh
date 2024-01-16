#!/bin/bash

##
## Case Name: multiple-pipeline
## Preconditions:
##    playback and capture features work well, they can be checked with
##    check-playback.sh and check-capture.sh
## Description:
##    Run multiple pipelines in parallel
##    Rule:
##      1. Playback mode: playback pipelines ONLY are used, test pipeline count
##         (OPT_VAL['c']) is respected, but maxed out with playback pipelines.
##      2. Capture mode: same with playback mode, but capture pipelines ONLY will
##         be used.
##      3. All pipelines mode: Run all playback and capture pipelines in parallel
##         by using the option '-f a' and set the number of pipelines with -c.
##         If you need to use all pipelines, set a high pipeline count such as -c 20.
## Case step:
##    1. acquire pipeline count that will be running in parallel
##    2. start playback or capture pipelines or all pipelines
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

OPT_NAME['f']='fill mode'
OPT_DESC['f']='fill mode, either playback (p) or capture (c) or any (a) for all pipelines'
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
MULTI_PIPELINE_FILTER='~pcm:Amplifier Reference & ~pcm:Port0'
max_count=0

# find playback or capture or both pipelines to get $PIPELINE_COUNT
case "$f_arg" in
    'p') type_filter='type:playback';;
    'c') type_filter='type:capture';;
    'a') type_filter='type:any';;
    *) die "not supported option $f_arg";;
esac
func_pipeline_export "$tplg" "$type_filter & ${MULTI_PIPELINE_FILTER}"

# respect number of pipelines requested but max will be real pipeline count
max_count=$(minvalue "${OPT_VAL['c']}" "$PIPELINE_COUNT")

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
        # shellcheck disable=SC2207
        idx_lst=($(seq 0 $((PIPELINE_COUNT - 1))))
    else
        # convert array to line, shuf to get random line, covert line to array
        # shellcheck disable=SC2207
        idx_lst=($(seq 0 $((PIPELINE_COUNT - 1)) | sed 's/ /\n/g' | shuf | xargs))
    fi

    for idx in "${idx_lst[@]}"
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
            func_run_pipeline_with_type "playback" "${MULTI_PIPELINE_FILTER}"
            func_run_pipeline_with_type "capture" "${MULTI_PIPELINE_FILTER}"
            ;;
        'c')
            tmp_count=$max_count
            func_run_pipeline_with_type "capture" "${MULTI_PIPELINE_FILTER}"
            func_run_pipeline_with_type "playback" "${MULTI_PIPELINE_FILTER}"
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

