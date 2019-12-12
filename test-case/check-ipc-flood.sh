#!/bin/bash

##
## Case Name: ipc flood
## Preconditions:
##    N/A
## Description:
##    check sof debug ipc function can success work
## Case step:
##    1. write target count to ipc_flood_count
##       echo 10000 > /sys/kernel/debug/sof/ipc_flood_count
## Expect result:
##    without kernel log
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['c']='cnt'      OPT_DESC_lst['c']='ipc loop count'
OPT_PARM_lst['c']=1         OPT_VALUE_lst['c']=10000

OPT_OPT_lst['f']='dfs'      OPT_DESC_lst['f']='system dfs file'
OPT_PARM_lst['f']=1         OPT_VALUE_lst['f']="/sys/kernel/debug/sof/ipc_flood_count"

func_opt_parse_option $*

lpc_loop_cnt=${OPT_VALUE_lst['c']}
ipc_flood_dfs=${OPT_VALUE_lst['f']}

[[ ! "$(sof-kernel-dump.sh|grep 'sof-audio'|grep 'Firmware debug build')" ]] && dlogw "${BASH_SOURCE[0]} need debug version firmware" && exit 2

func_lib_setup_kernel_last_line
func_lib_check_sudo

dlogi "Check sof debug fs environment"
[[ "$(sudo file $ipc_flood_dfs|grep 'No such file')" ]] && dlogw "${BASH_SOURCE[0]} need $ipc_flood_dfs to run the test case" && exit 2
dlogi "Checking ipc flood test!"
dlogc "sudo bash -c 'echo $lpc_loop_cnt > $ipc_flood_dfs'"
sudo bash -c "'echo $lpc_loop_cnt > $ipc_flood_dfs'"

sof-kernel-log-check.sh $KERNEL_LAST_LINE
[[ $? -ne 0 ]] && dloge "Catch error in kernel log" && exit 1

dlogi "Dumping test logs!"
dmesg | grep "IPC Flood count" -A 2

exit 0
