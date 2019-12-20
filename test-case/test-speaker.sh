#!/bin/bash

# TODO: case & descrption step need to confirm
##
## Case Name: test speaker test
## Preconditions:
##    N/A
## Description:
##    using speaker-test to do playback test
## Case step:
##    speaker-test on each playback pipelines
## Expect result:
##    speaker-test end without error
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='option of speaker-test'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=3

func_opt_add_common_TPLG
func_opt_add_common_sof_logger
func_opt_parse_option $*
tplg=${OPT_VALUE_lst['t']}
[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

func_pipeline_export $tplg "type:playback,both"
tcnt=${OPT_VALUE_lst['l']}
func_lib_setup_kernel_last_line
for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
do
    channel=$(func_pipeline_parse_value $idx channel)
    rate=$(func_pipeline_parse_value $idx rate)
    fmt=$(func_pipeline_parse_value $idx fmt)
    dev=$(func_pipeline_parse_value $idx dev)

    dlogc "speaker-test -D $dev -r $rate -c $channel -f $fmt -l $tcnt -t wav -P 8"
    speaker-test -D $dev -r $rate -c $channel -f $fmt -l $tcnt -t wav -P 8 2>&1 |tee $LOG_ROOT/result_$idx.txt
    resultRet=$?

    if [[ $resultRet -eq 0 ]]; then
        grep -nr -E "error|failed" $LOG_ROOT/result_$idx.txt
        if [[ $? -eq 0 ]]; then
            dloge "speaker test failed"
            exit 1
        fi
    fi
done

sof-kernel-log-check.sh $KERNEL_LAST_LINE
exit $?
