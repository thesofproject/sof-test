#!/usr/bin/env bash

##
## Case Name: simultaneous-playback-capture
## Preconditions:
##    N/A
## Description:
##    simultaneous running of aplay and arecord on "both" pipelines
##    Supports multiple topology files separated by colon (:) or comma (,)
## Case step:
##    1. Parse TPLG file(s) to get pipeline with type "both"
##    2. Run aplay and arecord
##    3. Check for aplay and arecord process existence
##    4. Sleep for given time period
##    5. Check for aplay and arecord process existence
##    6. Kill aplay & arecord processes
## Expect result:
##    aplay and arecord processes survive for entirety of test until killed
##    check kernel log and find no errors
##

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['t']='tplg'     OPT_DESC['t']="tplg file(s), separated by : or , default value is env TPLG: $TPLG"
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['w']='wait'     OPT_DESC['w']='sleep for wait duration'
OPT_HAS_ARG['w']=1         OPT_VAL['w']=5

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=1

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
wait_time=${OPT_VAL['w']}
loop_cnt=${OPT_VAL['l']}

start_test

# Support multiple topologies separated by colon (:) or comma (,)
# sof-tplgreader.py natively supports multiple files with comma separator
tplg="${tplg//,/:}"  # Normalize to colon first
# Parse and validate topology files
func_tplg_parse_and_validate "$tplg"
tplg_files="$TPLG_FILES"

dlogi "Processing $TPLG_COUNT topology file(s) for 'both' pipelines"

# get 'both' pcm: pipelines with same id but different types (playback + capture)
declare -A tmp_id_types  # Store "id:type" combinations seen
declare -A id_has_playback
declare -A id_has_capture
id_lst_str=""

# sof-tplgreader.py handles multiple files natively
# Parse output to find IDs with both playback and capture
while IFS= read -r line; do
    # Expected format: id=X;pcm=NAME;type=TYPE;...
    if [[ "$line" =~ id=([0-9]+)\;.*type=(playback|capture) ]]; then
        pid="${BASH_REMATCH[1]}"
        ptype="${BASH_REMATCH[2]}"
        key="${pid}:${ptype}"
        
        # Skip if we've seen this exact id:type combination (duplicate from multiple topologies)
        [[ -n "${tmp_id_types[$key]}" ]] && continue
        tmp_id_types["$key"]=1
        
        # Track which IDs have which types
        if [[ "$ptype" == "playback" ]]; then
            id_has_playback["$pid"]=1
        elif [[ "$ptype" == "capture" ]]; then
            id_has_capture["$pid"]=1
        fi
    fi
done < <(sof-tplgreader.py "$tplg_files" -d id pcm type -o)

# Find IDs that have both playback and capture
for pid in "${!id_has_playback[@]}"; do
    if [[ -n "${id_has_capture[$pid]}" ]]; then
        id_lst_str="${id_lst_str},${pid}"
    fi
done

# Clean up
unset tmp_id_types id_has_playback id_has_capture
id_lst_str=${id_lst_str/,/} # remove leading comma
[[ ${#id_lst_str} -eq 0 ]] && dlogw "no pipeline with both playback and capture capabilities found in $tplg" && exit 2
func_pipeline_export "$tplg" "id:$id_lst_str"

logger_disabled || func_lib_start_log_collect

func_error_exit()
{
    dloge "$*"
    kill_process "$aplay_pid" || true
    wait "$aplay_pid" 2>/dev/null || true
    kill_process "$arecord_pid" || true
    wait "$arecord_pid" 2>/dev/null || true
    exit 1
}

for i in $(seq 1 "$loop_cnt")
do
    # set up checkpoint for each iteration
    setup_kernel_check_point
    dlogi "===== Testing: (Loop: $i/$loop_cnt) ====="
    # following sof-tplgreader, split 'both' pipelines into separate playback & capture pipelines, with playback occurring first
    for order in $(seq 0 2 $(( "$PIPELINE_COUNT" - 1)))
    do
        idx=$order
        channel=$(func_pipeline_parse_value "$idx" channel)
        rate=$(func_pipeline_parse_value "$idx" rate)
        fmt=$(func_pipeline_parse_value "$idx" fmt)
        dev=$(func_pipeline_parse_value "$idx" dev)

        dlogc "aplay -D $dev -c $channel -r $rate -f $fmt /dev/zero -q &"
        aplay -D "$dev" -c "$channel" -r "$rate" -f "$fmt" /dev/zero -q &
        aplay_pid=$!

        idx=$(( order + 1 ))
        channel=$(func_pipeline_parse_value "$idx" channel)
        rate=$(func_pipeline_parse_value "$idx" rate)
        fmt=$(func_pipeline_parse_value "$idx" fmt)
        dev=$(func_pipeline_parse_value "$idx" dev)

        dlogc "arecord -D $dev -c $channel -r $rate -f $fmt /dev/null -q &"
        arecord -D "$dev" -c "$channel" -r "$rate" -f "$fmt" /dev/null -q &
        arecord_pid=$!

        dlogi "Preparing to sleep for $wait_time"
        sleep "$wait_time"

        # aplay/arecord processes should be persistent for sleep duration.
        dlogi "check pipeline after ${wait_time}s"
        kill -0 $aplay_pid ||
            func_error_exit "Error in aplay process after sleep."

        kill -0 $arecord_pid ||
            func_error_exit "Error in arecord process after sleep."

        # kill all live processes, successful end of test
        dlogc "killing all pipelines"
        kill_process "$aplay_pid" || true
        wait "$aplay_pid" 2>/dev/null || true
        kill_process "$arecord_pid" || true
        wait "$arecord_pid" 2>/dev/null || true

    done
    # check kernel log for each iteration to catch issues
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" || die "Caught error in kernel log"
done

