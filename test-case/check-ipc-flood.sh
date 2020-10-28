#!/bin/bash

##
## Case Name: ipc flood
## Preconditions:
##    N/A
## Description:
##    check sof debug ipc function can successfully work
## Case step:
##    1. write target count to ipc_flood_count
##       echo 10000 > /sys/kernel/debug/sof/ipc_flood_count
## Expect result:
##    no error in kernel log
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['c']='cnt'      OPT_DESC_lst['c']='ipc loop count'
OPT_PARM_lst['c']=1         OPT_VALUE_lst['c']=10000

OPT_OPT_lst['f']='dfs'      OPT_DESC_lst['f']='system dfs file'
OPT_PARM_lst['f']=1         OPT_VALUE_lst['f']="/sys/kernel/debug/sof/ipc_flood_count"

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=1

func_opt_parse_option "$@"

lpc_loop_cnt=${OPT_VALUE_lst['c']}
ipc_flood_dfs=${OPT_VALUE_lst['f']}
loop_cnt=${OPT_VALUE_lst['l']}

[[ ! "$(sof-kernel-dump.sh|grep 'sof-audio'|grep 'Firmware debug build')" ]] && dlogw "${BASH_SOURCE[0]} need debug version firmware" && exit 2

func_lib_setup_kernel_last_timestamp
func_lib_check_sudo

dlogi "Check sof debug fs environment"
[[ "$(sudo file $ipc_flood_dfs|grep 'No such file')" ]] && dlogw "${BASH_SOURCE[0]} need $ipc_flood_dfs to run the test case" && exit 2
dlogi "Checking ipc flood test!"

for i in $(seq 1 $loop_cnt)
do
    # cleanup dmesg buffer for each iteration
    sudo dmesg -c > /dev/null
    # set up timestamp for each iteration
    func_lib_setup_kernel_last_timestamp
    dlogi "===== [$i/$loop_cnt] loop Begin ====="
    dlogc "sudo bash -c 'echo $lpc_loop_cnt > $ipc_flood_dfs'"
    sudo bash -c "'echo $lpc_loop_cnt > $ipc_flood_dfs'"

    # check kernel log for each iteration to catch issues
    sof-kernel-log-check.sh $KERNEL_LAST_TIMESTAMP || die "Catch error in kernel log"

    dlogi "Dumping test logs!"
    dmesg | grep "IPC Flood count" -A 2

done
