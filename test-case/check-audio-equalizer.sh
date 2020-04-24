#!/bin/bash

##
## Case Name: check-audio-equalizer.sh
## Preconditions:
##    SOF Topology should have EQ component(s) in any pipeline
## Description:
##    check IIR/FIR config working
## Case step:
##    1. Check if the topology has a EQ component in it
##    2. Test with IIR config list
##    3. Test with FIR config list
## Expect result:
##    sof-ctl and aplay should return 0
##

# source from the relative path of current folder
source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['d']='duration' OPT_DESC_lst['d']='aplay duration in second'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=5

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=1

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

func_opt_parse_option "$@"
tplg=${OPT_VALUE_lst['t']}
duration=${OPT_VALUE_lst['d']}
loop_cnt=${OPT_VALUE_lst['l']}

# TODO: direct import only EQ pipeline
func_pipeline_export $tplg "type:playback"
sofcard=${SOFCARD:-0}

# Test equalizer
func_test_eq()
{
    local id=$1
    local conf=$2

    [ ! -f $conf ] && dloge "$conf not exist" && exit 1

    dlogc "sof-ctl -Dhw:$sofcard -n $id -s $conf"
    sof-ctl -Dhw:$sofcard -n $id -s $conf
    if [ $? -ne 0 ]; then
        dloge "Equalizer setting failure with $conf"
        return 1
    fi
    # test with aplay
    dlogc "aplay -D$dev -f $fmt -c $channel -r $rate /dev/zero -d $duration"
    aplay -D$dev -f $fmt -c $channel /dev/zero -d $duration
    if [ $? -ne 0 ]; then
        dloge "Equalizer test failure with $conf"
        return 1
    fi
    sleep 1
}

current_dir=$(dirname ${BASH_SOURCE[0]})

# initialized with negative value. If none of test is performed the test result will be failed.
result=1
failed_cnt=0

# TODO: direct import only EQ pipeline and loop for EQ pipeline only
for idx in $(seq 0 $(expr $PIPELINE_COUNT - 1))
do
    dlogi "$idx - total pipeline= $PIPELINE_COUNT"
    dev=$(func_pipeline_parse_value $idx dev)
    channel=$(func_pipeline_parse_value $idx channel)
    rate=$(func_pipeline_parse_value $idx rate)
    fmt=$(func_pipeline_parse_value $idx fmt)
    eq_support=$(func_pipeline_parse_value $idx eq)
    if [ -z "$eq_support" ]; then
        dlogi "None of FIR/IIF filter is available in this pipeline, skip"
        continue
    fi
    dlogi "eq_support= $eq_support"
    is_iir=$(echo $eq_support | grep -i iir | wc -l)
    is_fir=$(echo $eq_support | grep -i fir | wc -l)
    if [ $is_iir -ne $is_fir ]; then
        dlogi "no FIR or IIF filter is available in this pipeline, skip"
        continue
    fi

    dlogi "0. Get amixer control id for IIR and FIR"
    IIRid=`amixer -D hw:$sofcard controls | grep EQIIR| head -1| sed 's/numid=\([0-9]*\),.*/\1/'`
    if [ -z $IIRid ]; then
            dloge "can't find IIR filter"
            exit 1
    fi

    FIRid=`amixer -D hw:$sofcard controls | grep EQFIR| head -1| sed 's/numid=\([0-9]*\),.*/\1/'`
    if [ -z $FIRid ]; then
            dloge "can't find FIR filter"
            exit 1
    fi

    declare -a IIRList=($(ls -d ${current_dir}/eqctl/eq_iir_*.txt))
    nIIRList=${#IIRList[@]}
    dlogi "IIR list $nIIRList ${IIRList[*]}"
    declare -a FIRList=($(ls -d ${current_dir}/eqctl/eq_fir_*.txt))
    nFIRList=${#FIRList[@]}
    dlogi "FIR list $nFIRList ${FIRList[*]}"
    if [ $nIIRList ==  0 ] || [ $nFIRList ==  0 ]; then
        dloge "IIR or FIR flter coeff list error!"
	exit 1
    fi

    for i in $(seq 1 $loop_cnt)
    do
        dlogi "[$i/$loop_cnt] 1. Test IIR config list, IIR amixer control id=$IIRid"
        for config in ${IIRList[@]}; do
            func_test_eq $IIRid $current_dir/$config
            result=$?
            if [[ $result -ne 0 ]]; then
                dloge "Failed at $config"
                let failed_cnt++
            fi
        done

        dlogi "[$i/$loop_cnt] 2. Test FIR config list, FIR amixer control id=$FIRid"
        for config in ${FIRList[@]}; do
            func_test_eq $FIRid $current_dir/$config
            result=$?
            if [[ $result -ne 0 ]]; then
                dloge "Failed at $config"
                let failed_cnt++
            fi
        done
        dlogi "EQ test done: failed_cnt is $failed_cnt"
        if [ $failed_cnt -gt 0 ]; then
            exit 1
        fi
    done

done

exit $result

