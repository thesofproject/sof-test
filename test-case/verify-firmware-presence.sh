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

# source from the relative path of current folder
source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

func_opt_parse_option "$@"

path=$(sof-dump-status.py -P)
platform=$(sof-dump-status.py -p)
fw="$path/sof-$platform.ri"
dlogi "Checking file: $fw"
[[ ! -f $fw ]] && dloge "File $fw is not found!" && exit 1
dlogi "Found file: $(md5sum $fw|awk '{print $2, $1;}')"

exit 0
