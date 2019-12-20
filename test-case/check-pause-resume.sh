#!/bin/bash

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

OPT_OPT_lst['m']='mode'    OPT_DESC_lst['m']='test mode'
OPT_PARM_lst['m']=1         OPT_VALUE_lst['m']='playback'

OPT_OPT_lst['c']='count'    OPT_DESC_lst['c']='pause/resume repeat count'
OPT_PARM_lst['c']=1         OPT_VALUE_lst['c']=10

OPT_OPT_lst['w']='sleep'    OPT_DESC_lst['w']='sleep time between pause/resume'
OPT_PARM_lst['w']=1         OPT_VALUE_lst['w']=0.5

OPT_OPT_lst['d']='duration' OPT_DESC_lst['d']='duration time'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=10

OPT_OPT_lst['f']='file'     OPT_DESC_lst['f']='file name'
OPT_PARM_lst['f']=1         OPT_VALUE_lst['f']=''

func_opt_add_common_TPLG
func_opt_add_common_sof_logger
func_opt_parse_option $*

tplg=${OPT_VALUE_lst['t']}
test_mode=${OPT_VALUE_lst['m']}
repeat_count=${OPT_VALUE_lst['c']}
sleep_time=${OPT_VALUE_lst['w']}
duration=${OPT_VALUE_lst['d']}
#TODO: file name salt for capture
file_name=${OPT_VALUE_lst['f']}

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
        dloge "Invalid test mode: $test_mode (allow value : playback, capture)"
        exit 1
    ;;
esac

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

[[ -z $file_name ]] && file_name=$dummy_file

func_pipeline_export $tplg "type:$test_mode,both"
func_lib_setup_kernel_last_line
for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
do
    channel=$(func_pipeline_parse_value $idx channel)
    rate=$(func_pipeline_parse_value $idx rate)
    fmt=$(func_pipeline_parse_value $idx fmt)
    dev=$(func_pipeline_parse_value $idx dev)

    dlogi "Entering expect script with: $cmd -D $dev -r $rate -c $channel -f $fmt -vv -i -d $duration $file_name -q"

    expect <<END
spawn $cmd -D $dev -r $rate -c $channel -f $fmt -vv -i -d $duration $file_name -q
set i 0
expect {
    "*#*+*\%" {
        sleep $sleep_time
        send " "
        if { \$i < $repeat_count } {
            incr i
            exp_continue
        }
        exit 0
    }
}
exit 1
END
    #flush the output
    echo
    ret=$?
    if [ $ret -ne 0 ]; then
        sof-process-kill.sh
        [[ $? -ne 0 ]] && dlogw "Kill process catch error"
        exit $ret
    fi
done

sof-kernel-log-check.sh $KERNEL_LAST_LINE
exit $?
