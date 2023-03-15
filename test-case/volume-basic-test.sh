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
# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

volume_array=("0%" "10%" "20%" "30%" "40%" "50%" "60%" "70%" "80%" "90%" "100%")
OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=2

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

func_opt_parse_option "$@"
setup_kernel_check_point
tplg=${OPT_VAL['t']}
maxloop=${OPT_VAL['l']}

func_error_exit()
{
    dloge "$*"
    pkill -9 aplay
    exit 1
}

[[ -z $tplg ]] && die "Missing tplg file needed to run"
func_pipeline_export "$tplg" "type:playback"
logger_disabled || func_lib_start_log_collect

[[ $PIPELINE_COUNT -eq 0 ]] && die "Missing playback pipeline for aplay to run"
channel=$(func_pipeline_parse_value 0 channel)
rate=$(func_pipeline_parse_value 0 rate)
fmt=$(func_pipeline_parse_value 0 fmt)
dev=$(func_pipeline_parse_value 0 dev)

dlogc "aplay -D $dev -c $channel -r $rate -f $fmt /dev/zero &"
# play into background, this will wake up DSP and IPC. Need to clean after the test
aplay -D "$dev" -c "$channel" -r "$rate" -f "$fmt" /dev/zero &

sleep 1
[[ ! $(pidof aplay) ]] && die "aplay process is terminated too early"

sofcard=${SOFCARD:-0}
pgalist=($(amixer -c"$sofcard" controls | grep -i PGA | sed 's/ /_/g;' | awk -Fname= '{print $2}'))
dlogi "pgalist number = ${#pgalist[@]}"
[[ ${#pgalist[@]} -ne 0 ]] || skip_test "No PGA control is available"

for i in $(seq 1 $maxloop)
do
    setup_kernel_check_point
    dlogi "===== Round($i/$maxloop) ====="
    # TODO: need to check command effect
    for kctl in "${pgalist[@]}"
    do
        volctrl=$(echo "$kctl" | sed 's/_/ /g;')
        dlogi "$volctrl"

        for vol in "${volume_array[@]}"; do
            dlogc "amixer -c$sofcard cset name='$volctrl' $vol"
            amixer -c"$sofcard" cset name="$volctrl" "$vol" > /dev/null ||
                              func_error_exit "amixer return error, test failed"
        done
    done

    sleep 1

    dlogi "check dmesg for error"
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" ||
                      func_error_exit "dmesg has errors!"
done

#clean up background aplay
pkill -9 aplay

dlogi "Reset all PGA volume to 0dB"
reset_sof_volume || die "Failed to reset some PGA volume to 0dB."
