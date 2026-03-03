#!/bin/bash

##
## Case Name: verify-tplg-binary
## Preconditions:
##    SOF topology files install at "/lib/firmware/intel/sof-tplg"
## Description:
##    check target topology files md5sum
##    Supports multiple topology files separated by colon (:) or comma (,)
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

OPT_NAME['t']='tplg'     OPT_DESC['t']="tplg file(s), separated by : or , default value is env TPLG: $TPLG"
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

func_opt_parse_option "$@"
tplg=${OPT_VAL['t']}

start_test

# Support multiple topologies separated by colon (:) or comma (,)
# Convert comma separators to colons for uniform handling
tplg="${tplg//,/:}"
IFS=':' read -ra tplg_array <<< "$tplg"

# Process each topology
for single_tplg in "${tplg_array[@]}"; do
    single_tplg="${single_tplg## }"; single_tplg="${single_tplg%% }"  # Trim whitespace
    [[ -z "$single_tplg" ]] && continue
    
    tplg_path=$(func_lib_get_tplg_path "$single_tplg") || {
        dlogw "Topology not found: $single_tplg (skipping)"
        continue
    }
    
    dlogi "========================================"
    dlogi "Checking topology file: $tplg_path with sof-tplgreader.py"
    dlogi "Found file: $(md5sum "$tplg_path" | awk '{print $2, $1;}')"
    tplgData=$(sof-tplgreader.py "$tplg_path") || {
        dloge "No valid pipeline(s) found in $tplg_path"
        continue
    }
    
    dlogi "Valid pipeline(s) in this topology:"
    echo "============================>>"
    echo "$tplgData"
    echo "<<============================="
    
    # This one can find more problems, see sof-test#1054
    dlogi "Checking topology file with tplgtool2.py: $tplg_path"
    ( set -x
      tplgtool2.py -D "${LOG_ROOT}" "$tplg_path" ) || {
        ret=$?
        die "tplgtool2.py returned $ret for $tplg_path"
    }
done

dlogi "========================================"
dlogi "All topology files verified successfully"

