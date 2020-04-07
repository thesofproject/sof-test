#!/bin/bash

##
## Case Name: test reboot
## Preconditions:
##    N/A
## Description:
##    run reboot for the test
## Case step:
##    1. check system status is correct
##    2. wait for the delay time
##    3. trigger for the reboot
## Expect result:
##    Test execute without report error in the LOG
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=3

OPT_OPT_lst['t']='timeout'  OPT_DESC_lst['t']='timeout after system boot up'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']=30

OPT_OPT_lst['d']='delay'    OPT_DESC_lst['d']='delay time mapping to sub-case PM status'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=10

func_opt_parse_option $*

func_lib_check_sudo
loop_count=${OPT_VALUE_lst['l']}
delay=${OPT_VALUE_lst['d']}
timeout=${OPT_VALUE_lst['t']}

# write the total & current count to the status file
status_log=$LOG_ROOT/status.txt
echo "$loop_count $(uname -r)" >> $status_log
count=$(head -n 1 $status_log|awk '{print $1;}')
orig_kern=$(head -n 1 $status_log|awk '{print $2;}')
current=$[ $count - $loop_count ]
cur_kern=$(uname -r)

# compare kernel version
if [ "$orig_kern" != "$cur_kern" ]; then
    sed -i '$s/$/ fail/' $status_log
    dloge "Kernel version already been changed"
    exit 1
fi

# delay timeout for wait SOF load finish
# catch tplg file as the keyword
load_time=0
tplg=$(sof-get-default-tplg.sh)
while [ ! "$tplg" ]
do
    sleep 1
    load_time=$[ $load_time + 1 ]
    # trigger timeout detect
    if [ $load_time -ge $timeout ];then
        dloge "Wait too long for SOF load: $load_time s"
        exit 1
    fi
    tplg=$(sof-get-default-tplg.sh)
done

dlogi "SOF load took $load_time s to load TPLG success"

declare -a verify_lst
verify_lst=(${verify_lst[*]} "verify-firmware-presence.sh")
verify_lst=(${verify_lst[*]} "verify-kernel-module-load-probe.sh")
verify_lst=(${verify_lst[*]} "verify-pcm-list.sh")
verify_lst=(${verify_lst[*]} "verify-sof-firmware-load.sh")
verify_lst=(${verify_lst[*]} "verify-tplg-binary.sh")
verify_lst=(${verify_lst[*]} "check-runtime-pm-status.sh")

declare -A verify_opt_lst
verify_opt_lst['verify-pcm-list.sh']="-t $tplg"
verify_opt_lst['verify-tplg-binary.sh']="-t $tplg"
verify_opt_lst['check-runtime-pm-status.sh']="-t $tplg -l 1 -d $delay"

dlogi "Round: $current/$count Check status begin"
for i in ${verify_lst[*]}
do
    dlogc "$(dirname ${BASH_SOURCE[0]})/$i $(echo ${verify_opt_lst["$i"]})"
    $(dirname ${BASH_SOURCE[0]})/$i $(echo ${verify_opt_lst["$i"]})
    if [ $? -ne 0 ];then
        # last line add failed keyword
        sed -i '$s/$/ fail/' $status_log
        # record failed case:
        echo "$(dirname ${BASH_SOURCE[0]})/$i $(echo ${verify_opt_lst["$i"]})" >> $status_log
        dloge "$i: fail"
        exit 1
    else
        # last line add pass keyword
        dlogi "$i: pass" 
    fi
done

dlogi "Round $current: Status check finished"
sed -i '$s/$/ pass/' $status_log
[[ $loop_count -le 0 ]] && exit 0

dlogi "Do the prepare for the next round bootup"
# run the script for the next round
next_count=$[ $loop_count - 1 ]

full_cmd=$(ps -p $PPID -o args --no-header)
# parent process have current script name
# like: bash -c $0 .....
# here is string compare, [] will cause compare failed
if [[ "$full_cmd" =~ "bash -c" ]]; then
    full_cmd=${full_cmd#bash -c}
else
    full_cmd=$(ps -p $$ -o args --no-header)
    full_cmd=${full_cmd#\/bin\/bash}
fi

# some load will use '~' which is $HOME, but after system reboot, in rc.local $USER is root
# so the '~' will lead to the error path
full_cmd=$(echo $full_cmd|sed "s:~:$HOME:g")

# load script default value for the really full command
# add -d delay
[[ ! $(echo $full_cmd|grep "'-d $delay'") ]] && full_cmd=$(echo $full_cmd|sed "s:$0:& -d $delay:g")
# add -t timeout
[[ ! $(echo $full_cmd|grep "'-t $timeout'") ]] && full_cmd=$(echo $full_cmd|sed "s:$0:& -t $timeout:g")
# add -l loop_count
[[ ! $(echo $full_cmd|grep "'-l $loop_count'") ]] && full_cmd=$(echo $full_cmd|sed "s:$0:& -l $loop_count:g")
# now command will like: $0 -l loop_count -t timeout -d delay

# convert relative path to absolute path
full_cmd=$(echo $full_cmd|sed "s:$0:$(realpath $0):g")

# convert full current command to next round command
full_cmd=$(echo $full_cmd|sed "s:-l $loop_count:-l $next_count:g")

boot_file=/etc/rc.local
# if miss rc.local file let sof-boot-once.sh to create it
[[ ! -f $boot_file ]] && sudo sof-boot-once.sh

# change the file own & add write permission
sudo chmod u+w $boot_file
sudo chown $UID $boot_file
old_content="$(cat $boot_file|grep -v '^exit')"
# write the information to /etc/rc.local
# LOG_ROOT to make sure all tests, including sub-cases, write log to the same target folder
# DMESG_LOG_START_LINE to just keep last kernel bootup log
boot_once_flag=$(realpath $(which sof-boot-once.sh))
cat << END > $boot_file
$old_content

$boot_once_flag
export LOG_ROOT='$(realpath $LOG_ROOT)'
export DMESG_LOG_START_LINE=$(wc -l /var/log/kern.log|awk '{print $1;}')
bash -c '$full_cmd'

exit 0
END
# * restore file own to root
sudo chown 0 $boot_file

dlogc "reboot"
sudo reboot
