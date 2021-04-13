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

OPT_NAME['c']='cnt'      OPT_DESC['c']='ipc loop count'
OPT_HAS_ARG['c']=1         OPT_VAL['c']=10000

OPT_NAME['f']='dfs'      OPT_DESC['f']='system dfs file'
OPT_HAS_ARG['f']=1         OPT_VAL['f']="/sys/kernel/debug/sof/ipc_flood_count"

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=1

func_opt_parse_option "$@"

lpc_loop_cnt=${OPT_VAL['c']}
ipc_flood_dfs=${OPT_VAL['f']}
loop_cnt=${OPT_VAL['l']}

[[ ! "$(sof-kernel-dump.sh|grep 'sof-audio'|grep 'Firmware debug build')" ]] && dlogw "${BASH_SOURCE[0]} need debug version firmware" && exit 2

func_lib_check_sudo

dlogi "Check sof debug fs environment"
[[ "$(sudo file $ipc_flood_dfs|grep 'No such file')" ]] && dlogw "${BASH_SOURCE[0]} need $ipc_flood_dfs to run the test case" && exit 2
dlogi "Checking ipc flood test!"

for i in $(seq 1 $loop_cnt)
do
    # TODO: use journalctl to replace dmesg
    # cleanup dmesg buffer for each iteration
    sudo dmesg -c > /dev/null
    # set up timestamp for each iteration
    setup_kernel_check_point
    dlogi "===== [$i/$loop_cnt] loop Begin ====="
    dlogc "sudo bash -c 'echo $lpc_loop_cnt > $ipc_flood_dfs'"
    sudo bash -c "'echo $lpc_loop_cnt > $ipc_flood_dfs'"

    # check kernel log for each iteration to catch issues
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" || die "Caught error in kernel log"
    # TODO: use journalctl to replace dmesg
    dlogi "Dumping test logs!"
    dmesg | grep "IPC Flood count" -A 2
done
