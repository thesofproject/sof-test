#!/bin/bash

##
## Case Name: check-kmod-load-unload-after-playback
## Preconditions:
##    N/A
## Description:
##    check kernel module removal/insert process with playback before and after
## Case step:
##    1. enter loop for module remove / insert test
##    2. for each pcm type == playback or both:
##       start playback of duration OPT_VALUE_lst['d]'
##    3. check for playback errors
##    4. remove all loaded modules listed in sof_remove.sh
##       (only once, not per PCM)
##    5. check for rmmod errors
##    6. check for dmesg errors
##    7. insert all in-tree modules listed in sof_insert.sh
##       (only once, not per PCM)
##    8. check for successful sof-firmware boot
##    9. check for dmesg errors
##    10. for each pcm type == playback or both:
##        start playback of duration OPT_VALUE_lst['d]'
##    11. check for playback errors
##    12. loop to beginning (max OPT_VALUE_lst['l'])
## Expect result:
##    aplay is successful before module removal/insert process per PCM
##    removal/insert process is successful (only onc --- not per PCM)
##    aplay is succesful after module removal/insert process per PCM
##    check kernel log and find no errors
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['l']='loop'
OPT_DESC_lst['l']='loop of PCM aplay check - module remove / insert - PCM aplay check'
OPT_PARM_lst['l']=1          OPT_VALUE_lst['l']=2

OPT_OPT_lst['d']='duration' OPT_DESC_lst['d']='duration of playback process'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=3

OPT_OPT_lst['p']='pulseaudio'   OPT_DESC_lst['p']='disable pulseaudio on the test process'
OPT_PARM_lst['p']=0             OPT_VALUE_lst['p']=1

func_opt_parse_option $*
tplg=${OPT_VALUE_lst['t']}
loop_cnt=${OPT_VALUE_lst['l']}
pb_duration=${OPT_VALUE_lst['d']}

func_pipeline_export $tplg "type:playback,both"

func_lib_check_sudo
# overwirte the subscript: test-case LOG_ROOT environment
# so when load the test-case in current script
# the test-case will write the log to the store folder LOG_ROOT
# which is current script log folder
export LOG_ROOT=$LOG_ROOT

if [ ${OPT_VALUE_lst['p']} -eq 1 ];then
    func_lib_disable_pulseaudio
fi

$(dirname ${BASH_SOURCE[0]})/check-playback.sh -l 1 -t $tplg -d $pb_duration
ret=$?
[[ $ret -ne 0 ]] && dloge "aplay check failed" && exit $ret

for counter in $(seq 1 $loop_cnt)
do
    dlogi "Starting iteration $counter of $loop_cnt"

    # logic: if this case disable pulseaudio, the sub case don't need to disable pulseaudio
    # if this case don't need to disable pulseaudio, the subcase also don't need to disable pluseaudio
    $(dirname ${BASH_SOURCE[0]})/check-kmod-load-unload.sh -l 1 -p
    ret=$?
    [[ $ret -ne 0 ]] && dloge "kmod reload failed" && exit $ret

    $(dirname ${BASH_SOURCE[0]})/check-playback.sh -l 1 -t $tplg -d $pb_duration
    ret=$?
    [[ $ret -ne 0 ]] && dloge "aplay check failed" && exit $ret
done

# successful exit
exit 0
