#!/bin/bash

##
## Case Name: verify-firmware-presence
## Preconditions:
##    SOF firmware install at "/lib/firmware/intel/sof"
## Description:
##    check target platform firmware file
## Case step:
##    1. check if target platform firmware exists
##    2. dump fw file md5sum
## Expect result:
##    list target firmware md5sum
##

set -e

# source from the relative path of current folder
# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

func_opt_parse_option "$@"
setup_kernel_check_point

start_test

path=$(sof-dump-status.py -P)
platform=$(sof-dump-status.py -p)
fw="$path/sof-$platform.ri"
dlogi "Checking file: $fw"
[ -f "$fw" ] || die "File $fw is not found!"
dlogi "Found file: $(md5sum "$fw"|awk '{print $2, $1;}')"
