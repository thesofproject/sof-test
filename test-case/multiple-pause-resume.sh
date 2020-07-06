#!/bin/bash

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

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=3

OPT_OPT_lst['c']='count'    OPT_DESC_lst['c']='combine test pipeline count'
OPT_PARM_lst['c']=1         OPT_VALUE_lst['c']=2

OPT_OPT_lst['r']='loop'     OPT_DESC_lst['r']='pause resume repeat count'
OPT_PARM_lst['r']=1         OPT_VALUE_lst['r']=3

OPT_OPT_lst['i']='min'      OPT_DESC_lst['i']='random range min value, unit is ms'
OPT_PARM_lst['i']=1         OPT_VALUE_lst['i']='100'

OPT_OPT_lst['a']='max'      OPT_DESC_lst['a']='random range max value, unit is ms'
OPT_PARM_lst['a']=1         OPT_VALUE_lst['a']='200'

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

func_opt_parse_option "$@"

repeat_count=${OPT_VALUE_lst['r']}
loop_count=${OPT_VALUE_lst['l']}
# configure random value range
rnd_min=${OPT_VALUE_lst['i']}
rnd_max=${OPT_VALUE_lst['a']}
rnd_range=$[ $rnd_max - $rnd_min ]
[[ $rnd_range -le 0 ]] && dlogw "Error random range scope [ min:$rnd_min - max:$rnd_max ]" && exit 2

tplg=${OPT_VALUE_lst['t']}
func_pipeline_export $tplg "type:any"

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

func_lib_setup_kernel_last_line

declare -a pipeline_idx_lst
declare -a cmd_idx_lst
declare -a file_idx_lst

# merge all pipeline to the 1 group
for i in $(seq 0 $(expr $PIPELINE_COUNT - 1))
do
    pipeline_idx_lst=(${pipeline_idx_lst[*]} $i)
    type=$(func_pipeline_parse_value $i type)
    if [ "$type" == "playback" ];then
        cmd_idx_lst=(${cmd_idx_lst[*]} "aplay")
        file_idx_lst=(${file_idx_lst[*]} "/dev/zero")
    elif [ "$type" == "capture" ];then
        cmd_idx_lst=(${cmd_idx_lst[*]} "arecord")
        file_idx_lst=(${file_idx_lst[*]} "/dev/null")
    elif [ "$type" == "both" ];then
        cmd_idx_lst=(${cmd_idx_lst[*]} "aplay")
        file_idx_lst=(${file_idx_lst[*]} "/dev/zero")
        # both include playback & capture, so duplicate it
        pipeline_idx_lst=(${pipeline_idx_lst[*]} $i)
        cmd_idx_lst=(${cmd_idx_lst[*]} "arecord")
        file_idx_lst=(${file_idx_lst[*]} "/dev/null")
    else
        die "Unknow pipeline type: $type"
    fi
done

# get the min value of TPLG:'pipeline count' with Case:'pipeline count'
[[ ${#pipeline_idx_lst[*]} -gt ${OPT_VALUE_lst['c']} ]] && max_count=${OPT_VALUE_lst['c']} || max_count=${#pipeline_idx_lst[*]}
[[ $max_count -eq 1 ]] && dlogw "pipeline count is 1, don't need to run this case" && exit 2

# create combination list 
declare -a pipeline_combine_lst
for i in $(sof-combinatoric.py -n ${#pipeline_idx_lst[*]} -p $max_count)
do
    # convert combine string to combine element
    pipeline_combine_str="$(echo $i|sed 's/,/ /g')"
    pipeline_combine_lst=("${pipeline_combine_lst[@]}" "$pipeline_combine_str")
done
[[ ${#pipeline_combine_lst[@]} -eq 0 ]] && dlogw "pipeline combine is empty" && exit 2

func_pause_resume_pipeline()
{
    local idx=${pipeline_idx_lst[$1]} cmd=${cmd_idx_lst[$1]} file=${file_idx_lst[$1]}
    local channel=$(func_pipeline_parse_value $idx channel)
    local rate=$(func_pipeline_parse_value $idx rate)
    local fmt=$(func_pipeline_parse_value $idx fmt)
    local dev=$(func_pipeline_parse_value $idx dev)
    local pcm=$(func_pipeline_parse_value $idx pcm)
    local type=$(func_pipeline_parse_value $idx type)
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

max_wait_time=$[ 10 * $repeat_count ]

for i in $(seq 1 $loop_count)
do
    dlogi "===== Loop count( $i / $loop_count ) ====="
    sudo dmesg -c >/dev/null
    for pipeline_combine_str in "${pipeline_combine_lst[@]}"
    do
        unset pid_lst
        declare -a pid_lst
        for idx in $(echo $pipeline_combine_str)
        do
            func_pause_resume_pipeline $idx
            pid_lst=(${pid_lst[*]} $!)
        done
        # wait for expect script finished
        dlogi "wait for expect process finished"
        i=$max_wait_time
        while [ $i -gt 0 ]
        do
            i=$[ $i - 1 ]
            sleep 1s
            [[ ! "$(pidof expect)" ]] && break
        done
        # fix aplay/arecord last output
        echo 
        if [ "$(pidof expect)" ]; then
            dloge "Still have expect process not finished after wait for $max_wait_time"
            # now dump process
            ps -ef |grep -E 'aplay|arecord'
            exit 1
        fi
        # now check for all expect quit status
        # dump the pipeline combine, because pause resume will have too many operation log
        for idx in $(echo $pipeline_combine_str)
        do
            pipeline_index=${pipeline_idx_lst[$idx]}
            pcm=$(func_pipeline_parse_value $pipeline_index pcm)
            dlogi "pipeline: $pcm with ${cmd_idx_lst[$idx]}"
        done
        dlogi "Check expect exit status"
        for pid in ${pid_lst[*]}
        do
            wait $pid
            [[ $? -ne 0 ]] && die "pause resume is exit status error"
        done
    done
    sof-kernel-log-check.sh 0 || die "Catch error in dmesg"
done

sof-kernel-log-check.sh $KERNEL_LAST_LINE
exit $?
