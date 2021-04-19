#!/bin/bash

set -e

##
## Case Name: verify-kernel-module-load-probe
## Description:
##    lsmod and check snd and sof relative module list
##    fail if no sof module found
## Case step:
##    lsmod | grep "sof"
## Expect result:
##    find sof relative module

# source from the relative path of current folder
source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

func_opt_parse_option "$@"

setup_kernel_check_point

dlogi "Checking if sof relative modules loaded"
dlogc "lsmod | grep \"sof\""
lsmod | grep "sof"
[[ $? -ne 0 ]] && dloge "No available sof module found! Dumping lsmod:" && lsmod && exit 1

exit 0
