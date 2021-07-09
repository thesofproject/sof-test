#!/bin/bash

set -e

##
## Case Name: Run multiple pipeline for pause resume
## Preconditions:
##    N/A
## Description:
##    pickup multiple pipline to do pause resume
##    fake pause/resume with expect
##    expect sleep for sleep time then mocks spacebar keypresses ' ' to
##    cause resume action
## Case step:
##    1. run 1st pipeline
##    2. pickup any other pipeline
##    3. use expect to fake pause/resume in each pipeline
##    4. go through with tplg file
## Expect result:
##    no errors occur for either process
##

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['t']='tplg'     OPT_DESC['t']="tplg file, default value is env TPLG: $TPLG"
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=5

OPT_NAME['c']='count'    OPT_DESC['c']='combine test pipeline count'
OPT_HAS_ARG['c']=1         OPT_VAL['c']=2

OPT_NAME['r']='loop'     OPT_DESC['r']='pause resume repeat count'
OPT_HAS_ARG['r']=1         OPT_VAL['r']=5

# pause/resume interval will be a random value bounded by the min and max values below
OPT_NAME['i']='min'      OPT_DESC['i']='pause/resume transition min value, unit is ms'
OPT_HAS_ARG['i']=1         OPT_VAL['i']='20'

OPT_NAME['a']='max'      OPT_DESC['a']='pause/resume transition max value, unit is ms'
OPT_HAS_ARG['a']=1         OPT_VAL['a']='50'

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

func_opt_parse_option "$@"

repeat_count=${OPT_VAL['r']}
loop_count=${OPT_VAL['l']}
# configure random value range
rnd_min=${OPT_VAL['i']}
rnd_max=${OPT_VAL['a']}
rnd_range=$((rnd_max - rnd_min))
[[ $rnd_range -le 0 ]] && dlogw "Error random range scope [ min:$rnd_min - max:$rnd_max ]" && exit 2

tplg=${OPT_VAL['t']}
func_pipeline_export "$tplg" "type:any"

logger_disabled || func_lib_start_log_collect

declare -a pipeline_idx_lst
declare -a cmd_idx_lst
declare -a file_idx_lst

# merge all pipeline to the 1 group
for i in $(seq 0 $((PIPELINE_COUNT - 1)))
do
    pipeline_idx_lst=("${pipeline_idx_lst[*]}" "$i")
    type=$(func_pipeline_parse_value "$i" type)
    if [ "$type" == "playback" ];then
        cmd_idx_lst=("${cmd_idx_lst[*]}" "aplay")
        file_idx_lst=("${file_idx_lst[*]}" "/dev/zero")
    elif [ "$type" == "capture" ];then
        cmd_idx_lst=("${cmd_idx_lst[*]}" "arecord")
        file_idx_lst=("${file_idx_lst[*]}" "/dev/null")
    elif [ "$type" == "both" ];then
        cmd_idx_lst=("${cmd_idx_lst[*]}" "aplay")
        file_idx_lst=("${file_idx_lst[*]}" "/dev/zero")
        # both include playback & capture, so duplicate it
        pipeline_idx_lst=("${pipeline_idx_lst[*]}" "$i")
        cmd_idx_lst=("${cmd_idx_lst[*]}" "arecord")
        file_idx_lst=("${file_idx_lst[*]}" "/dev/null")
    else
        die "Unknow pipeline type: $type"
    fi
done

# get the min value of TPLG:'pipeline count' with Case:'pipeline count'
[[ ${#pipeline_idx_lst[*]} -gt ${OPT_VAL['c']} ]] && max_count=${OPT_VAL['c']} || max_count=${#pipeline_idx_lst[*]}
[[ $max_count -eq 1 ]] && dlogw "pipeline count is 1, don't need to run this case" && exit 2

# create combination list
declare -a pipeline_combine_lst
for i in $(sof-combinatoric.py -n ${#pipeline_idx_lst[*]} -p "$max_count")
do
    # convert combine string to combine element
    pipeline_combine_str="${i//,/ }"
    pipeline_combine_lst=("${pipeline_combine_lst[@]}" "$pipeline_combine_str")
done
[[ ${#pipeline_combine_lst[@]} -eq 0 ]] && dlogw "pipeline combine is empty" && exit 2

func_pause_resume_pipeline()
{
    local idx=${pipeline_idx_lst[$1]} cmd=${cmd_idx_lst[$1]} file=${file_idx_lst[$1]}
    local channel; channel=$(func_pipeline_parse_value "$idx" channel)
    local rate; rate=$(func_pipeline_parse_value "$idx" rate)
    local fmt; fmt=$(func_pipeline_parse_value "$idx" fmt)
    local dev; dev=$(func_pipeline_parse_value "$idx" dev)
    local pcm; pcm=$(func_pipeline_parse_value "$idx" pcm)
    local type; type=$(func_pipeline_parse_value "$idx" type)
    # expect is tcl language script
    #   expr rand(): produces random numbers between 0 and 1
    #   after ms: Ms must be an integer giving a time in milliseconds.
    #       The command sleeps for ms milliseconds and then returns.
    dlogi "$pcm to command: $cmd -D $dev -r $rate -c $channel -f $fmt -vv -i $file -q"
    expect <<END &
spawn $cmd -D $dev -r $rate -c $channel -f $fmt -vv -i $file -q
set i 1
expect {
    "*#*+*\%" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) pcm'$pcm' cmd'$cmd' id'$idx': Wait for \$sleep_t ms before pause"
        send " "
        after \$sleep_t
        exp_continue
    }
    "*PAUSE*" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) pcm'$pcm' cmd'$cmd' id'$idx': Wait for \$sleep_t ms before resume"
        send " "
        after \$sleep_t
        incr i
        if { \$i > $repeat_count } { exit 0 }
        exp_continue
    }
}
exit 1
END
}

# to prevent infinite loop, 5 second per a repeat is plenty
max_wait_time=$((5 * repeat_count)) 

for i in $(seq 1 $loop_count)
do
    dlogi "===== Loop count( $i / $loop_count ) ====="
    # set up checkpoint for each iteration
    setup_kernel_check_point
    for pipeline_combine_str in "${pipeline_combine_lst[@]}"
    do
        unset pid_lst
        declare -a pid_lst
        for idx in $pipeline_combine_str
        do
            func_pause_resume_pipeline "$idx"
            pid_lst=("${pid_lst[*]}" $!)
        done
        # wait for expect script finished
        dlogi "wait for expect process finished"
        iwait=$max_wait_time
        while [ $iwait -gt 0 ]
        do
            iwait=$((iwait - 1))
            sleep 1s
            [[ ! "$(pidof expect)" ]] && break
        done
        # fix aplay/arecord last output
        echo
        if [ "$(pidof expect)" ]; then
            dloge "Still have expect process not finished after wait for $max_wait_time"
            # list aplay/arecord process and kill them
            pgrep -a aplay && pkill -9 aplay
            pgrep -a arecord && pkill -9 arecord
            exit 1
        fi
        # now check for all expect quit status
        # dump the pipeline combine, because pause resume will have too many operation log
        for idx in $pipeline_combine_str
        do
            pipeline_index=${pipeline_idx_lst[$idx]}
            pcm=$(func_pipeline_parse_value "$pipeline_index" pcm)
            dlogi "pipeline: $pcm with ${cmd_idx_lst[$idx]}"
        done
        dlogi "Check expect exit status"
        for pid in ${pid_lst[*]}
        do
            wait "$pid" || {
                sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" || true
                die "pause resume PID $pid had non-zero exit status"
            }
        done
    done
    # check kernel log for each iteration to catch issues
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" || die "Caught error in kernel log"
done

