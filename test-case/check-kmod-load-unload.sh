#!/bin/bash

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
##    8. loop to beginning (max OPT_VALUE_lst['r'])
## Expect result:
##    kernel module removal / insert process is successful
##    check kernel log and find no errors
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['l']='loop_cnt'
OPT_DESC_lst['l']='remove / insert module loop count -- per device'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=2

OPT_OPT_lst['p']='pulseaudio'   OPT_DESC_lst['p']='disable pulseaudio on the test process'
OPT_PARM_lst['p']=0             OPT_VALUE_lst['p']=1

func_opt_parse_option $*
func_lib_setup_kernel_last_line

loop_cnt=${OPT_VALUE_lst['l']}
usb_audio_module="snd_usb_audio"
kern_log="/var/log/kern.log"
keyword_info=""

PATH="${PATH%%:*}/kmod:$PATH"
func_lib_check_sudo

if [ ${OPT_VALUE_lst['p']} -eq 1 ];then
    func_lib_disable_pulseaudio
fi

for idx in $(seq 1 $loop_cnt)
do
    dlogi "Starting iteration $idx of $loop_cnt"
    ## - 1: remove module section
    func_lib_setup_kernel_last_line

    dlogi "run kmod/sof-kmod-remove.sh"
    sudo sof_remove.sh
    [[ $? -ne 0 ]] && dloge "remove modules error" && exit 1

    ## - 1a: check for errors after removal
    dlogi "checking for general errors after kmod unload with sof-kernel-log-check tool"
    sof-kernel-log-check.sh $KERNEL_LAST_LINE
    [[ $? -ne 0 ]] && \
        dloge "error found after kmod unload is real error, failing" && \
        exit 1

    func_lib_setup_kernel_last_line
    dlogi "run kmod/sof_insert.sh"
    sudo sof_insert.sh
    [[ $? -ne 0 ]] && dloge "insert modules error" && exit
    sleep 1

    ## - 2a: check for errors after insertion
    dlogi "checking for general errors after kmod insert with sof-kernel-log-check tool"
    sof-kernel-log-check.sh $KERNEL_LAST_LINE

    dlogi "checking for fw_boot success"
    keyword_info=$(dmesg |grep sof-audio | grep 'boot complete')
    [[ ! "$keyword_info" ]] && \
        dloge "Error: Boot Complete not found in dmesg, fw_boot empty" && \
        exit 1

    # successful remove/insert module pass
    dlogi "==== completed boot firmware: $idx of $loop_cnt ===="
    # pulseaudio deamon will detect the snd_sof_pci device after 3s
    # so after 2s snd_sof_pci device will in used status which is block current case logic
    # here the logic is to check snd_sof_pci status is not in used status, the max delay is 10s
    sleep 1
    for i in $(seq 1 10)
    do
        [[ "X$(awk '/^snd_sof_pci/ {print $3;}' /proc/modules)" == "X0" ]] && break
        sleep 1
    done

done

exit 0
