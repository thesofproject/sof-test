#!/bin/bash

##
## Case Name: verify PCM list with tplg file
## Preconditions:
##    driver already inserted with modprobe
## Description:
##    using /proc/asound/pcm to compare with tplg content
## Case step:
##    1. load tplg file to get pipeline list string
##    2. load /proc/asound/pcm to get pcm list string
##    3. compare string list
## Expect result:
##    pipeline list is same as pcm list
##

# source from the relative path of current folder
source "$(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh"

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="${TPLG:-}"

func_opt_parse_option "$@"
tplg=${OPT_VALUE_lst['t']}

tplg_path=`func_lib_get_tplg_path "$tplg"`
[[ "$?" != "0" ]] && die "No available topology for this test case"

# hijack DMESG_LOG_START_LINE which refer dump kernel log in exit function
DMESG_LOG_START_LINE=$(sof-get-kernel-line.sh|tail -n 1 |awk '{print $1;}')

tplg_str="$(sof-tplgreader.py $tplg_path -d id pcm type -o)"
pcm_str="$(sof-dump-status.py -i ${SOFCARD:-0})"

dlogc "sof-tplgreader.py $tplg_file -d id pcm type -o"
dlogi "Pipeline(s) from topology file:"
echo "$tplg_str"
dlogc "sof-dump-status.py -i ${SOFCARD:-0}"
dlogi "Pipeline(s) from system:"
echo "$pcm_str"

if [[ "$tplg_str" != "$pcm_str" ]]; then
    dloge "Pipeline(s) from topology don't match pipeline(s) from system"
    dlogi "Dump aplay -l"
    aplay -l
    dlogi "Dump arecord -l"
    arecord -l
    sof-kernel-dump.sh > $LOG_ROOT/kernel.txt
    exit 1
else
    dlogi "Pipeline(s) from topology match pipeline(s) from system"
fi
exit 0
