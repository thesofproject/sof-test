#!/bin/bash

##
## Case Name: stress test reboot
## Preconditions:
##    N/A
## Description:
##    run reboot for the stress test
##    default duration is 10s
##    default loop count is 3
## Case step:
##    1. check system status is correct
##    2. wait for the Random value
##    3. trigger for the reboot
## Expect result:
##    Test execute without report error in the LOG
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=5

func_opt_parse_option $*

func_lib_check_sudo
func_lib_trigger_stress

loop_count=${OPT_VALUE_lst['l']}

[[ $loop_count -le 0 ]] && exit 0
# write the orig & status count to the status file
echo $loop_count >> $STRESS_STATUS_LOG
count=$(head -n 1 $STRESS_STATUS_LOG|awk '{print $1;}')
# because write record by desc
current=$[ $count - $loop_count + 1 ]

dlogi "Round: $current/$count"|tee -a $STRESS_OUTPUT_LOG

# verify-pcm-list.sh & verify-tplg-binary.sh need TPLG file
export TPLG=$(sof-get-default-tplg.sh)

declare -a verify_lst
verify_lst=(${verify_lst[*]} "verify-firmware-presence.sh")
verify_lst=(${verify_lst[*]} "verify-kernel-module-load-probe.sh")
verify_lst=(${verify_lst[*]} "verify-pcm-list.sh")
verify_lst=(${verify_lst[*]} "verify-sof-firmware-load.sh")
verify_lst=(${verify_lst[*]} "verify-tplg-binary.sh")

# here will write double line into $STRESS_OUTPUT_LOG
# because for the 1st round those information write by nohup command redirect
# but after system reboot the nohup redirect is missing
dlogi "Check status begin"|tee -a $STRESS_OUTPUT_LOG
for i in ${verify_lst[*]}
do
    $(dirname ${BASH_SOURCE[0]})/$i
    if [ $? -ne 0 ];then
        # last line add failed keyword
        sed -i '$s/$/ fail/' $STRESS_STATUS_LOG
        dlogi "$i: fail" |tee -a $STRESS_OUTPUT_LOG
        exit 1
    else
        # last line add pass keyword
        dlogi "$i: pass" |tee -a $STRESS_OUTPUT_LOG
    fi
done
dlogi "Status check finished"
sed -i '$s/$/ pass/' $STRESS_STATUS_LOG

# run the script for the next round
loop_count=$[ $loop_count - 1 ]

# Store the environment for the next round load this script
dlogi "Setup the environment for next round bootup" |tee -a $STRESS_OUTPUT_LOG

declare -A exp_lst
exp_lst['TPLG']=$TPLG
exp_lst['LOG_ROOT']=$LOG_ROOT
# just keep the last dmesg bootup kernel line for the success
exp_lst['DMESG_LOG_START_LINE']=$(wc -l /var/log/kern.log|awk '{print $1;}')

for key in ${!exp_lst[@]}
do
    sudo sof-boot-once.sh export $key=${exp_lst[$key]}
done

# run this script for next boot up round
dlogi "sof-boot-onece.sh ${BASH_SOURCE[0]} -l $loop_count" |tee -a $STRESS_OUTPUT_LOG
sudo sof-boot-once.sh ${BASH_SOURCE[0]} -l $loop_count

# template delay before reboot
sleep 1s

sudo reboot
