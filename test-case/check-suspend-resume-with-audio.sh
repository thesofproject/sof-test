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

TESTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd)
# shellcheck source=case-lib/lib.sh
source "${TESTDIR}"/../case-lib/lib.sh

OPT_NAME['l']='loop'     OPT_DESC['l']='suspend/resume loop count'
OPT_HAS_ARG['l']=1       OPT_VAL['l']=3

OPT_NAME['T']='type'     OPT_DESC['T']="suspend/resume type from /sys/power/mem_sleep"
OPT_HAS_ARG['T']=1       OPT_VAL['T']=""

OPT_NAME['S']='sleep'    OPT_DESC['S']='suspend/resume command:rtcwake sleep duration'
OPT_HAS_ARG['S']=1       OPT_VAL['S']=5

OPT_NAME['w']='wait'     OPT_DESC['w']='idle time after suspend/resume wakeup'
OPT_HAS_ARG['w']=1       OPT_VAL['w']=5

OPT_NAME['r']='random'   OPT_DESC['r']="Randomly setup wait/sleep time, this option will overwrite s & w option"
OPT_HAS_ARG['r']=0       OPT_VAL['r']=0

OPT_NAME['m']='mode'     OPT_DESC['m']='alsa application type: playback/capture'
OPT_HAS_ARG['m']=1       OPT_VAL['m']='playback'

OPT_NAME['t']='tplg'     OPT_DESC['t']="tplg file, default value is env TPLG: $TPLG"
OPT_HAS_ARG['t']=1       OPT_VAL['t']="$TPLG"

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0           OPT_VAL['s']=1

OPT_NAME['f']='file'     OPT_DESC['f']='file name'
OPT_HAS_ARG['f']=1       OPT_VAL['f']=''

OPT_NAME['P']='pipelines'    OPT_DESC['P']="run test case on specified pipelines"
OPT_HAS_ARG['P']=1           OPT_VAL['P']="id:any"

func_opt_parse_option "$@"
setup_kernel_check_point
func_lib_check_sudo

tplg=${OPT_VAL['t']}

start_test
logger_disabled || func_lib_start_log_collect

# overwrite the subscript: test-case LOG_ROOT environment
# so when load the test-case in current script
# the test-case will write the log to the store folder LOG_ROOT
# which is current script log folder
export LOG_ROOT=$LOG_ROOT

if [ "${OPT_VAL['m']}" == "playback" ]; then
    cmd='aplay'     dummy_file='/dev/zero'
elif [ "${OPT_VAL['m']}" == "capture" ]; then
    cmd='arecord'   dummy_file='/dev/null'
else
    dlogw "Error alsa application type: ${OPT_VAL['m']}"
fi
[[ -z $file_name ]] && file_name=$dummy_file

func_pipeline_export "$tplg" "type:${OPT_VAL['m']} & ${OPT_VAL['P']}"

opt_arr=(-l "${OPT_VAL['l']}")
if [ "${OPT_VAL['T']}" ]; then
    opt_arr+=(-T "${OPT_VAL['T']}")
fi
if [ ${OPT_VAL['r']} -eq 0  ]; then
    opt_arr+=(-S "${OPT_VAL['S']}" -w "${OPT_VAL['w']}")
else
    opt_arr+=(-r)
fi

for idx in $(seq 0 $((PIPELINE_COUNT - 1)))
do
    # set up checkpoint for each iteration
    setup_kernel_check_point
    # store local checkpoint as we have sub-test
    LOCAL_CHECK_POINT="$KERNEL_CHECKPOINT"
    channel=$(func_pipeline_parse_value "$idx" channel)
    rate=$(func_pipeline_parse_value "$idx" rate)
    fmt=$(func_pipeline_parse_value "$idx" fmt)
    dev=$(func_pipeline_parse_value "$idx" dev)
    snd=$(func_pipeline_parse_value "$idx" snd)
    dlogi "Run $TYPE command for the background"
    cmd_args="$cmd -D$dev -r $rate -c $channel -f $fmt $file_name -q"
    dlogc "$cmd_args"
    $cmd -D"$dev" -r "$rate" -c "$channel" -f "$fmt" "$file_name" -q  & process_id=$!
    # delay for process run
    sleep 1
    # check process status is correct
    sof-process-state.sh "$process_id" || {
        func_lib_lsof_error_dump "$snd"
        dloge "error process state of $cmd"
        dlogi "dump ps for aplay & arecord"
        pgrep -fla "aplay|arecord"
        dlogi "dump ps for child process"
        ps --ppid $$ -f
        exit 1
    }
    "${TESTDIR}"/check-suspend-resume.sh "${opt_arr[@]}"  || die "suspend resume failed"

    # check kernel log for each iteration to catch issues
    sof-kernel-log-check.sh "$LOCAL_CHECK_POINT" || die "Caught error in kernel log"

    # check process status is correct
    sof-process-state.sh $process_id || {
        func_lib_lsof_error_dump "$snd"
        dloge "process status is abnormal"
        dlogi "dump ps for aplay & arecord"
        pgrep -fla "aplay|arecord"
        dlogi "dump ps for child process"
        ps --ppid $$ -f
        exit 1
    }
    dlogi "Killing $cmd_args"
    kill -9 $process_id || true
done

