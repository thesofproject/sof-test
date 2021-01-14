#!/bin/bash

##
## Case Name: verify-tplg-binary
## Preconditions:
##    SOF topology files install at "/lib/firmware/intel/sof-tplg"
## Description:
##    check target topology files md5sum
## Case step:
##    1. check if topology files exist
##    2. dump tplg files md5sum
## Expect result:
##    list topology files md5sum
##

set -e

# source from the relative path of current folder
# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

func_opt_parse_option "$@"
tplg=${OPT_VAL['t']}

tplg_path=`func_lib_get_tplg_path "$tplg"`
[[ "$?" != "0" ]] && die "No available topology for this test case"

dlogi "Checking topology file: $tplg_path"
dlogi "Found file: $(md5sum $tplg_path|awk '{print $2, $1;}')"
tplgData=$(sof-tplgreader.py $tplg_path 2>/dev/null)
[[ -z "$tplgData" ]] && die "No valid pipeline(s) found in $tplg_path"
dlogi "Valid pipeline(s) in this topology:"
echo "===========================>>"
echo "$tplgData"
echo "<<==========================="

exit 0
