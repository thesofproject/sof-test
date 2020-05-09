#!/bin/bash

##
## Case Name: volume-basic-test
## Preconditions:
##    aplay should work
##    At least one PGA control should be available
## Description:
##    Set volume from 0% to 100% to each PGA
## Case step:
##    1. Start aplay
##    2. Set amixer command to set volume on each PGA
## Expect result:
##    command line check with $? without error
##

# source from the relative path of current folder
source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

volume_array=("0%" "10%" "20%" "30%" "40%" "50%" "60%" "70%" "80%" "90%" "100%")
OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=2

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

func_opt_parse_option "$@"
tplg=${OPT_VALUE_lst['t']}
maxloop=${OPT_VALUE_lst['l']}

func_error_exit()
{
    dloge "$*"
    pkill -9 aplay
    exit 1
}

[[ -z $tplg ]] && dlogw "Missing tplg file needed to run" && exit 1
func_pipeline_export $tplg "type:playback"
[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

[[ $PIPELINE_COUNT -eq 0 ]] && dlogw "Missing playback pipeline for aplay to run" && exit 1
channel=$(func_pipeline_parse_value 0 channel)
rate=$(func_pipeline_parse_value 0 rate)
fmt=$(func_pipeline_parse_value 0 fmt)
dev=$(func_pipeline_parse_value 0 dev)

dlogc "aplay -D $dev -c $channel -r $rate -f $fmt /dev/zero &"
# play into back ground, this will wake up DSP and IPC. Need to clean after the test
aplay -D $dev -c $channel -r $rate -f $fmt /dev/zero &

sleep 1
[[ ! $(pidof aplay) ]] && dloge "$pid process is terminated too early" && exit 1

sofcard=${SOFCARD:-0}
pgalist=($(amixer -c$sofcard controls | grep PGA | sed 's/ /_/g;' | awk -Fname= '{print $2}'))
dlogi "pgalist number = ${#pgalist[@]}"
[[ ${#pgalist[@]} -eq 0 ]] && func_error_exit "No PGA control is available"

for i in $(seq 1 $maxloop)
do
    func_lib_setup_kernel_last_line
    dlogi "===== Round($i/$maxloop) ====="
    # TODO: need to check command effect
    for i in "${pgalist[@]}"
    do
        volctrl=$(echo $i | sed 's/_/ /g;')
        dlogi "$volctrl"

        for vol in ${volume_array[@]}; do
            dlogc "amixer -c$sofcard cset name='$volctrl' $vol"
            amixer -c$sofcard cset name="$volctrl" $vol > /dev/null
            [[ $? -ne 0 ]] && func_error_exit "amixer return error, test failed"
        done
    done

    sleep 1

    dlogi "check dmesg for error"
    sof-kernel-log-check.sh $KERNEL_LAST_LINE
    [[ $? -ne 0 ]] && func_error_exit "dmesg has errors!"
done

#clean up background aplay
pkill -9 aplay

exit 0
