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

# source from the relative path of current folder
source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

func_opt_parse_option $*
tplg=${OPT_VALUE_lst['t']}

[ -z $tplg ] && dloge "need to give topology files for check!" && exit 1
dlogi "checking the topology file: $tplg ..."
tplg_str=$tplg
((ret=0))
while [ ${#tplg_str} -gt 0 ]
do
    # left ',' 1st filed
    tplg_file=${tplg_str%%,*}
    # expect left ',' 1st filed
    tplg_str=${tplg_str#*,}
    [ "$tplg_file" == "$tplg_str" ] && tplg_str=""
    if [ -f "$tplg_file" ]; then
        tplg_file="$tplg_file"
    elif [ -f "$TPLG_ROOT/$tplg_file" ]; then
        tplg_file="$TPLG_ROOT/$tplg_file"
    else
        dloge "Couldn't find target TPLG file $tplg_file"
	((ret=1))
	continue
    fi
    dlogi "Found file: $(md5sum $tplg_file|awk '{print $2, $1;}')"
    tplgData=$(sof-tplgreader.py $tplg_file 2>/dev/null)
    [[ -z $tplgData ]] && dloge "$tplg_file doesn't have any valid pipelines ..." && ((ret=1)) && continue
done

exit $ret
