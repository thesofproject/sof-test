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
TOPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
source "$TOPDIR/case-lib/lib.sh"


volume_array=("0%" "10%" "20%" "30%" "40%" "50%" "60%" "70%" "80%" "90%" "100%")
OPT_NAME['t']='tplg'     OPT_DESC['t']="tplg file, default value is env TPLG: $TPLG"
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=2

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

set -e

func_opt_parse_option "$@"
setup_kernel_check_point
tplg=${OPT_VAL['t']}
maxloop=${OPT_VAL['l']}

func_lib_enable_pipewire

start_test

[[ -z $tplg ]] && die "Missing tplg file needed to run"
func_pipeline_export "$tplg" "type:playback"
logger_disabled || func_lib_start_log_collect

[[ $PIPELINE_COUNT -eq 0 ]] && die "Missing playback pipeline for aplay to run"

initialize_audio_params "0"
# play into background, this will wake up DSP and IPC. Need to clean after the test
aplay_opts -D "$dev" -c "$channel" -r "$rate" -f "$fmts" /dev/zero &
sleep 1
check_alsa_tool_process
sofcard=${SOFCARD:-0}

# https://mywiki.wooledge.org/BashFAQ/024 why cant I pipe data to read?
readarray -t pgalist < <("$TOPDIR"/tools/topo_vol_kcontrols.py "$tplg")

# This (1) provides some logging (2) avoids skip_test if amixer fails
get_sof_controls "$sofcard"
dlogi "pgalist number = ${#pgalist[@]}"
[[ ${#pgalist[@]} -ne 0 ]] || skip_test "No PGA control is available"

for i in $(seq 1 "$maxloop")
do
    setup_kernel_check_point
    dlogi "===== Round($i/$maxloop) ====="
    # TODO: need to check command effect
    for volctrl in "${pgalist[@]}"
    do
        dlogi "$volctrl"

        for vol in "${volume_array[@]}"; do
            set_sof_volume "$sofcard" "$volctrl" "$vol" ||
                              kill_playrecord_die "mixer return error, test failed"
        done
    done

    sleep 1

    dlogi "check dmesg for error"
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" ||
                      kill_playrecord_die "dmesg has errors!"
done

func_lib_disable_pipewire

#clean up background play record
kill_play_record || true

dlogi "Reset all PGA volume to 0dB"
reset_sof_volume || die "Failed to reset some PGA volume to 0dB."
