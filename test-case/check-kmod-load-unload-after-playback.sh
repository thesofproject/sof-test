#!/bin/bash

set -e

##
## Case Name: check-kmod-load-unload-after-playback
## Preconditions:
##    N/A
## Description:
##    check kernel module removal/insert process with playback before and after
## Case step:
##    1. enter loop for module remove / insert test
##    2. for each pcm type == playback:
##       start playback of duration OPT_VAL['d]'
##    3. check for playback errors
##    4. remove all loaded modules listed in sof_remove.sh
##       (only once, not per PCM)
##    5. check for rmmod errors
##    6. check for dmesg errors
##    7. insert all in-tree modules listed in sof_insert.sh
##       (only once, not per PCM)
##    8. check for successful sof-firmware boot
##    9. check for dmesg errors
##    10. for each pcm type == playback:
##        start playback of duration OPT_VAL['d]'
##    11. check for playback errors
##    12. loop to beginning (max OPT_VAL['l'])
## Expect result:
##    aplay is successful before module removal/insert process per PCM
##    removal/insert process is successful (only onc --- not per PCM)
##    aplay is succesful after module removal/insert process per PCM
##    check kernel log and find no errors
##

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh
case_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)

OPT_NAME['t']='tplg'     OPT_DESC['t']="tplg file, default value is env TPLG: $TPLG"
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['l']='loop'
OPT_DESC['l']='loop of PCM aplay check - module remove / insert - PCM aplay check'
OPT_HAS_ARG['l']=1          OPT_VAL['l']=2

OPT_NAME['d']='duration' OPT_DESC['d']='duration of playback process'
OPT_HAS_ARG['d']=1         OPT_VAL['d']=3

OPT_NAME['p']='pulseaudio'   OPT_DESC['p']='disable pulseaudio on the test process'
OPT_HAS_ARG['p']=0             OPT_VAL['p']=1

func_opt_parse_option "$@"
tplg=${OPT_VAL['t']}
loop_cnt=${OPT_VAL['l']}
pb_duration=${OPT_VAL['d']}

func_pipeline_export "$tplg" "type:playback"

func_lib_check_sudo

if [ ${OPT_VAL['p']} -eq 1 ];then
    func_lib_disable_pulseaudio
fi

"$case_dir"/check-playback.sh -l 1 -t $tplg -d $pb_duration ||
    die "aplay check failed"

for counter in $(seq 1 $loop_cnt)
do
    # Only collect the latest success/failure logs
    setup_kernel_check_point
    dlogi "===== Starting iteration $counter of $loop_cnt ====="

    # logic: if this case disables pulseaudio, the sub case does not need to disable pulseaudio
    # if this case does not need to disable pulseaudio, the subcase also does not need to disable pluseaudio
    "$case_dir"/check-kmod-load-unload.sh -l 1 -p ||
        die "kmod reload failed"

    dlogi "wait dsp power status to become suspended"
    for i in $(seq 1 15)
    do
        # Here we pass a hardcoded 0 to python script, and need to ensure
        # DSP is the first audio pci device in 'lspci', this is true unless
        # we have a third-party pci sound card installed.
        [[ $(sof-dump-status.py --dsp_status 0) == "unsupported" ]] &&
            dlogi "platform doesn't support runtime pm, skip waiting" && break
        [[ $(sof-dump-status.py --dsp_status 0) == "suspended" ]] && break
        sleep 1
        if [ "$i" -ge 15 ]; then
            die "dsp is not suspended after 15s, end test"
        fi
    done

    "$case_dir"/check-playback.sh -l 1 -t $tplg -d $pb_duration ||
        die "aplay check failed"
done
