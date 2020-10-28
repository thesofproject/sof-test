#!/bin/bash

set -e

##
## Case Name: check suspend/resume with audio status
## Preconditions:
##    N/A
## Description:
##    Run the suspend/resume command to check audio device in use status
## Case step:
##    1. switch suspend/resume operation
##    2. run the audio command to the background
##    3. use rtcwake -m mem command to do suspend/resume
##    4. check command return value
##    5. check dmesg errors
##    6. check wakeup increase
##    7. kill audio command
##    8. check dmesg errors
## Expect result:
##    suspend/resume recover
##    check kernel log and find no errors
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='suspend/resume loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=3

OPT_OPT_lst['T']='type'     OPT_DESC_lst['T']="suspend/resume type from /sys/power/mem_sleep"
OPT_PARM_lst['T']=1         OPT_VALUE_lst['T']=""

OPT_OPT_lst['S']='sleep'    OPT_DESC_lst['S']='suspend/resume command:rtcwake sleep duration'
OPT_PARM_lst['S']=1         OPT_VALUE_lst['S']=5

OPT_OPT_lst['w']='wait'     OPT_DESC_lst['w']='idle time after suspend/resume wakeup'
OPT_PARM_lst['w']=1         OPT_VALUE_lst['w']=5

OPT_OPT_lst['r']='random'   OPT_DESC_lst['r']="Randomly setup wait/sleep time, this option will overwrite s & w option"
OPT_PARM_lst['r']=0         OPT_VALUE_lst['r']=0

OPT_OPT_lst['m']='mode'     OPT_DESC_lst['m']='alsa application type: playback/capture'
OPT_PARM_lst['m']=1         OPT_VALUE_lst['m']='playback'

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

OPT_OPT_lst['f']='file'     OPT_DESC_lst['f']='file name'
OPT_PARM_lst['f']=1         OPT_VALUE_lst['f']=''

func_opt_parse_option "$@"
func_lib_check_sudo
func_lib_setup_kernel_last_line

tplg=${OPT_VALUE_lst['t']}
[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

# overwrite the subscript: test-case LOG_ROOT environment
# so when load the test-case in current script
# the test-case will write the log to the store folder LOG_ROOT
# which is current script log folder
export LOG_ROOT=$LOG_ROOT

if [ "${OPT_VALUE_lst['m']}" == "playback" ]; then
    cmd='aplay'     dummy_file='/dev/zero'
elif [ "${OPT_VALUE_lst['m']}" == "capture" ]; then
    cmd='arecord'   dummy_file='/dev/null'
else
    dlogw "Error alsa application type: ${OPT_VALUE_lst['m']}"
fi
[[ -z $file_name ]] && file_name=$dummy_file

func_pipeline_export "$tplg" "type:${OPT_VALUE_lst['m']}"

if [ "${OPT_VALUE_lst['T']}" ]; then
    opt="-l ${OPT_VALUE_lst['l']} -T ${OPT_VALUE_lst['T']}"
else
    opt="-l ${OPT_VALUE_lst['l']}"
fi
if [ ${OPT_VALUE_lst['r']} -eq 0  ]; then
    opt="$opt -S ${OPT_VALUE_lst['S']} -w ${OPT_VALUE_lst['w']}"
else
    opt="$opt -r"
fi

for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
do
    channel=$(func_pipeline_parse_value $idx channel)
    rate=$(func_pipeline_parse_value $idx rate)
    fmt=$(func_pipeline_parse_value $idx fmt)
    dev=$(func_pipeline_parse_value $idx dev)
    pcm=$(func_pipeline_parse_value $idx pcm)
    snd=$(func_pipeline_parse_value $idx snd)
    dlogi "Run $TYPE command for the background"
    cmd_args="$cmd -D$dev -r $rate -c $channel -f $fmt $file_name -q"
    dlogc "$cmd_args"
    $cmd -D$dev -r $rate -c $channel -f $fmt $file_name -q  & process_id=$!
    # delay for process run
    sleep 1
    # check process status is correct
    sof-process-state.sh $process_id
    if [ $? -ne 0 ]; then
        func_lib_lsof_error_dump $snd
        dloge "error process state of $cmd"
        dlogi "dump ps for aplay & arecord"
        ps -ef |grep -E 'aplay|arecord'
        dlogi "dump ps for child process"
        ps --ppid $$ -f
        exit 1
    fi
    $(dirname ${BASH_SOURCE[0]})/check-suspend-resume.sh $(echo $opt)
    ret=$?
    [[ $ret -ne 0 ]] && dloge "suspend resume failed" && exit $ret
    # check process status is correct
    sof-process-state.sh $process_id
    if [ $? -ne 0 ]; then
        func_lib_lsof_error_dump $snd
        dloge "process status is abnormal"
        dlogi "dump ps for aplay & arecord"
        ps -ef |grep -E 'aplay|arecord'
        dlogi "dump ps for child process"
        ps --ppid $$ -f
        exit 1
    fi
    dlogi "Killing $cmd_args"
    kill -9 $process_id
    sof-kernel-log-check.sh 0 || die "Catch error in dmesg"
done

# check full log
sof-kernel-log-check.sh $KERNEL_LAST_LINE
