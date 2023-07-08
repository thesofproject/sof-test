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

OPT_NAME['t']='tplg'     OPT_DESC['t']="tplg file, default value is env TPLG: $TPLG"
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

func_opt_parse_option "$@"
setup_kernel_check_point
tplg=${OPT_VAL['t']}

tplg_path=$(func_lib_get_tplg_path "$tplg") ||
    die "No available topology ($tplg) for this test case"

dlogi "Checking topology file: $tplg_path with sof-tplgreader.py"
dlogi "Found file: $(md5sum "$tplg_path" | awk '{print $2, $1;}')"
tplgData=$(sof-tplgreader.py "$tplg_path") ||
    die "No valid pipeline(s) found in $tplg_path"

dlogi "Valid pipeline(s) in this topology:"
echo "===========================>>"
echo "$tplgData"
echo "<<==========================="

main()
{
    # This one can find more problems, see sof-test#1054
    dlogi "Checking topology file with tplgtool2.py: $tplg_path"
    ( set -x
      tplgtool2.py -D "${LOG_ROOT}" "$tplg_path" ) || {
        ret=$?
        die "tplgtool2.py returned $ret"
    }
}

main

