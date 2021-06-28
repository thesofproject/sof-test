#!/bin/bash

set -e

##
## Case Name: check-kmod-load-unload
## Preconditions:
##    N/A
## Description:
##    check kernel module removal/insert process
## Case step:
##    1. enter loop through the module remove / insert process
##    2. remove all loaded modules listed in sof_remove.sh
##    3. check for rmmod errors
##    4. check for dmesg errors
##    5. insert all in-tree modules listed in sof_insert.sh
##    6. check for successful sof-firmware boot
##    7. check for dmesg errors
##    8. loop to beginning (max OPT_VAL['r'])
## Expect result:
##    kernel module removal / insert process is successful
##    check kernel log and find no errors
##

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['l']='loop_cnt'
OPT_DESC['l']='remove / insert module loop count -- per device'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=2

OPT_NAME['p']='pulseaudio'   OPT_DESC['p']='disable pulseaudio on the test process'
OPT_HAS_ARG['p']=0             OPT_VAL['p']=1

func_opt_parse_option "$@"
setup_kernel_check_point

loop_cnt=${OPT_VAL['l']}

PATH="${PATH%%:*}/kmod:$PATH"
func_lib_check_sudo 'unloading modules'

if [ ${OPT_VAL['p']} -eq 1 ];then
    func_lib_disable_pulseaudio
fi

# Enable DEVRES debug log dynamically, this is very verbose
# it should be disabled at the end of this test
enable_devres_debug_log

for idx in $(seq 1 $loop_cnt)
do
    dlogi "===== Starting iteration $idx of $loop_cnt ====="
    ## - 1: remove module section
    setup_kernel_check_point

    # After module removal, it takes about 10s for "aplay -l" to show
    # device list, within this 10s, it shows "no soundcard found". Here
    # we wait dsp status to workaround this.
    dlogi "wait dsp power status to become suspended"
    for i in $(seq 1 15)
    do
        # Here we pass a hardcoded 0 to python script, and need to ensure
        # DSP is the first audio pci device in 'lspci', this is true unless
        # we have a third-party pci sound card installed.
        if [[ $(sof-dump-status.py --dsp_status 0) == "unsupported" ]]; then
            dlogi "platform doesn't support runtime pm, skip waiting"
            break
        fi
        [[ $(sof-dump-status.py --dsp_status 0) == "suspended" ]] && break
        sleep 1
        if [ "$i" -eq 15 ]; then
            die "dsp is not suspended after 15s, end test"
        fi
    done

    dlogi "run kmod/sof-kmod-remove.sh"
    sudo sof_remove.sh || die "remove modules error"

    ## - 1a: check for errors after removal
    dlogi "checking for general errors after kmod unload with sof-kernel-log-check tool"
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" ||
        die "error found after kmod unload is real error, failing"

    setup_kernel_check_point
    dlogi "run kmod/sof_insert.sh"
    sudo sof_insert.sh || die "insert modules error"

    ## - 2a: check for errors after insertion
    dlogi "checking for general errors after kmod insert with sof-kernel-log-check tool"
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" ||
        die "Found error(s) in kernel log after module insertion"

    dlogi "checking if firmware is loaded successfully"
    "$(dirname "${BASH_SOURCE[0]}")"/verify-sof-firmware-load.sh ||
         die "Failed to load firmware after module insertion"

    # successful remove/insert module pass
    dlogi "==== firmware boot complete: $idx of $loop_cnt ===="

    # After the last module insertion, it still takes about 10s for 'aplay -l' to show device
    # list. We need to wait before aplay can function. Here, wait dsp status to suspend to
    # avoid influence on next test case.
    i=0
    while dsp_status=$(sof-dump-status.py --dsp_status 0); do
        # ignore platforms that do not support runtime pm
        if [[ "$dsp_status" == 'unsupported' ]] ||
               [[ "$dsp_status" == 'suspended' ]]; then
            break
        fi
        if [ "$((i++))" -ge 15 ]; then
            die "After 15s DSP status is: $dsp_status"
        fi
        sleep 1
    done
done

disable_devres_debug_log
