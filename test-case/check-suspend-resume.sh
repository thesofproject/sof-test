#!/bin/bash

##
## Case Name: check suspend/resume status
## Preconditions:
##    N/A
## Description:
##    Run the suspend/resume command to check device status
## Case step:
##    1. switch suspend/resume operation
##    2. use rtcwake -m mem command to do suspend/resume
##    3. check command return value
##    4. check dmesg errors
##    5. check wakeup increase
## Expect result:
##    suspend/resume recover
##    check kernel log and find no errors
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

random_min=3    # wait time should >= 3 for other device wakeup from sleep
random_max=20

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=5

OPT_OPT_lst['T']='type'    OPT_DESC_lst['T']="suspend/resume type from /sys/power/mem_sleep"
OPT_PARM_lst['T']=1         OPT_VALUE_lst['T']=""

OPT_OPT_lst['S']='sleep'    OPT_DESC_lst['S']='suspend/resume command:rtcwake sleep duration'
OPT_PARM_lst['S']=1         OPT_VALUE_lst['S']=5

OPT_OPT_lst['w']='wait'     OPT_DESC_lst['w']='idle time after suspend/resume wakeup'
OPT_PARM_lst['w']=1         OPT_VALUE_lst['w']=5

OPT_OPT_lst['r']='random'   OPT_DESC_lst['r']="Randomly setup wait/sleep time, range is [$random_min-$random_max], this option will overwrite s & w option"
OPT_PARM_lst['r']=0         OPT_VALUE_lst['r']=0

func_opt_parse_option "$@"
func_lib_check_sudo
func_lib_setup_kernel_last_line

type=${OPT_VALUE_lst['T']}
# switch type
if [ "$type" ]; then
    # check for type value effect
    [[ ! "$(cat /sys/power/mem_sleep|grep $type)" ]] && dloge "useless type option" && exit 2
    dlogc "sudo bash -c 'echo $type > /sys/power/mem_sleep'"
    sudo bash -c "'echo $type > /sys/power/mem_sleep'"
fi
dlogi "Current suspend/resume type mode: $(cat /sys/power/mem_sleep)"

loop_count=${OPT_VALUE_lst['l']}
declare -a sleep_lst wait_lst

if [ ${OPT_VALUE_lst['r']} -eq 1 ]; then
    # create random number list
    for i in $(seq 1 $loop_count)
    do
        sleep_lst[$i]=$(func_lib_get_random $random_max $random_min)
        wait_lst[$i]=$(func_lib_get_random $random_max $random_min)
    done
else
    for i in $(seq 1 $loop_count)
    do
        sleep_lst[$i]=${OPT_VALUE_lst['S']}
        wait_lst[$i]=${OPT_VALUE_lst['w']}
    done
fi

for i in $(seq 1 $loop_count)
do
    dlogi "Round($i/$loop_count)"
    # cleanup dmesg befor run case
    sudo dmesg --clear
    sleep_count=$(cat /sys/power/wakeup_count)
    dlogc "Run the command: rtcwake -m mem -s ${sleep_lst[$i]}"
    sudo rtcwake -m mem -s ${sleep_lst[$i]}
    [[ $? -ne 0 ]] && dloge "rtcwake return value error" && exit 1
    dlogc "sleep for ${wait_lst[$i]}"
    sleep ${wait_lst[$i]}
    dlogi "Check for the kernel log status"
    wake_count=$(cat /sys/power/wakeup_count)
    # sof-kernel-log-check script parameter number is 0/Non-Number will force check from dmesg
    sof-kernel-log-check.sh 0 || {
        dloge "Catch error in dmesg" && exit 1
    }
    # check wakeup count correct
    [[ $wake_count -le $sleep_count ]] && dloge "suspend/resume didn't happen, because /sys/power/wakeup_count does not increase" && exit 1
done

# check full log
sof-kernel-log-check.sh $KERNEL_LAST_LINE
exit $?
