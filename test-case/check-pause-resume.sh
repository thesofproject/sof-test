#!/bin/bash

set -e

##
## Case Name: check-pause-resume
## Preconditions:
##    N/A
## Description:
##    playback/capture on each pipeline and feak pause/resume with expect
##    expect sleep for sleep time then mocks spacebar keypresses ' ' to
##    cause resume action
## Case step:
##    1. aplay/arecord on PCM
##    2. use expect to fake pause/resume
## Expect result:
##    no error happen for aplay/arecord
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['m']='mode'     OPT_DESC_lst['m']='test mode'
OPT_PARM_lst['m']=1         OPT_VALUE_lst['m']='playback'

OPT_OPT_lst['c']='count'    OPT_DESC_lst['c']='pause/resume repeat count'
OPT_PARM_lst['c']=1         OPT_VALUE_lst['c']=10

OPT_OPT_lst['f']='file'     OPT_DESC_lst['f']='file name'
OPT_PARM_lst['f']=1         OPT_VALUE_lst['f']=''

OPT_OPT_lst['i']='min'      OPT_DESC_lst['i']='random range min value, unit is ms'
OPT_PARM_lst['i']=1         OPT_VALUE_lst['i']='100'

OPT_OPT_lst['a']='max'      OPT_DESC_lst['a']='random range max value, unit is ms'
OPT_PARM_lst['a']=1         OPT_VALUE_lst['a']='200'

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

OPT_OPT_lst['S']='filter_string'   OPT_DESC_lst['S']="run this case on specified pipelines"
OPT_PARM_lst['S']=1             OPT_VALUE_lst['S']="id:any"

func_opt_parse_option "$@"

tplg=${OPT_VALUE_lst['t']}
test_mode=${OPT_VALUE_lst['m']}
repeat_count=${OPT_VALUE_lst['c']}
#TODO: file name salt for capture
file_name=${OPT_VALUE_lst['f']}
# configure random value range
rnd_min=${OPT_VALUE_lst['i']}
rnd_max=${OPT_VALUE_lst['a']}
rnd_range=$[ $rnd_max - $rnd_min ]
[[ $rnd_range -le 0 ]] && dlogw "Error random range scope [ min:$rnd_min - max:$rnd_max ]" && exit 2

case $test_mode in
    "playback")
        cmd=aplay
        dummy_file=/dev/zero
    ;;
    "capture")
        cmd=arecord
        dummy_file=/dev/null
    ;;
    *)
        die "Invalid test mode: $test_mode (allow value : playback, capture)"
    ;;
esac

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

[[ -z $file_name ]] && file_name=$dummy_file

func_pipeline_export "$tplg" "type:$test_mode & ${OPT_VALUE_lst['S']}"
func_lib_setup_kernel_last_timestamp
for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
do
    channel=$(func_pipeline_parse_value $idx channel)
    rate=$(func_pipeline_parse_value $idx rate)
    fmt=$(func_pipeline_parse_value $idx fmt)
    dev=$(func_pipeline_parse_value $idx dev)
    snd=$(func_pipeline_parse_value $idx snd)

    dlogi "Entering expect script with: $cmd -D $dev -r $rate -c $channel -f $fmt -vv -i $file_name -q"

    # expect is tcl language script
    #   expr rand(): produces random numbers between 0 and 1
    #   after ms: Ms must be an integer giving a time in milliseconds.
    #       The command sleeps for ms milliseconds and then returns.
    expect <<END
spawn $cmd -D $dev -r $rate -c $channel -f $fmt -vv -i $file_name -q
set i 1
expect {
    "*#*+*\%" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) Wait for \$sleep_t ms before pause"
        send " "
        after \$sleep_t
        exp_continue
    }
    "*PAUSE*" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) Wait for \$sleep_t ms before resume"
        send " "
        after \$sleep_t
        incr i
        if { \$i > $repeat_count } { exit 0 }
        exp_continue
    }
}
exit 1
END
    ret=$?
    #flush the output
    echo
    if [ $ret -ne 0 ]; then
        func_lib_lsof_error_dump $snd
        sof-process-kill.sh
        [[ $? -ne 0 ]] && dlogw "Kill process catch error"
        exit $ret
    fi
    # sof-kernel-log-check script parameter number is 0/Non-Number will force check from dmesg
    sof-kernel-log-check.sh 0 || die "Catch error in dmesg"
done

sof-kernel-log-check.sh $KERNEL_LAST_TIMESTAMP
exit $?
