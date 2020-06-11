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
my_dir=$(dirname "${BASH_SOURCE[0]}")
source "$my_dir"/../case-lib/lib.sh

OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']="tplg file, default value is env TPLG: $TPLG"
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

# import only EQ pipeline from topology
func_pipeline_export $tplg "eq:any"
sofcard=${SOFCARD:-0}

# Test equalizer
func_test_eq()
{
    local id=$1
    local conf=$2

    dlogc "sof-ctl -Dhw:$sofcard -n $id -s $conf"
    sof-ctl -Dhw:"$sofcard" -n "$id" -s "$conf" || {
        dloge "Equalizer setting failure with $conf"
        return 1
    }

    dlogc "$cmd -D $dev -f $fmt -c $channel -r $rate -d $duration $dummy_file"
    $cmd -D "$dev" -f "$fmt" -c "$channel" -r "$rate" -d "$duration" "$dummy_file" || {
        dloge "Equalizer test failure with $conf"
        return 1
    }
    sleep 1
}

# this function performs IIR/FIR filter test
# param1 must be must be iir or fir
func_test_filter()
{
    local testfilter=$1
    dlogi "Get amixer control id for $testfilter"
    # TODO: Need to match alsa control id with the filter in the pipeline,
    #       currently the test discards EQ pipelines except first one.
    Filterid=$(amixer -D hw:"$sofcard" controls | sed -n -e "/eq${testfilter}/I "'s/numid=\([0-9]*\),.*/\1/p' | head -1)
    if [ -z "$Filterid" ]; then
        die "can't find $testfilter"
    fi

    declare -a FilterList=($(ls -d "${my_dir}"/eqctl/eq_"${testfilter}"_*.txt))
    nFilterList=${#FilterList[@]}
    dlogi "$testfilter list, num= $nFilterList, coeff files= ${FilterList[*]}"
    if [ "$nFilterList" -eq  0 ]; then
        die "$testfilter flter coeff list error!"
    fi

    for i in $(seq 1 $loop_cnt)
    do
        dlogi "===== [$i/$loop_cnt] Test $testfilter config list, $testfilter amixer control id=$Filterid ====="
        for config in "${FilterList[@]}"; do
            func_test_eq "$Filterid" "$my_dir/$config" || {
                dloge "EQ test failed with $config"
                : $((failed_cnt++))
            }
        done

        dlogi "$testfilter test done: failed_cnt is $failed_cnt"
        if [ $failed_cnt -gt 0 ]; then
            exit 1
        fi
    done
}

failed_cnt=0

for idx in $(seq 0 "$((PIPELINE_COUNT-1))")
do
    dlogi "$idx - total pipeline= $PIPELINE_COUNT"
    dev=$(func_pipeline_parse_value "$idx" dev)
    channel=$(func_pipeline_parse_value "$idx" channel)
    rate=$(func_pipeline_parse_value "$idx" rate)
    fmt=$(func_pipeline_parse_value "$idx" fmt)
    type=$(func_pipeline_parse_value "$idx" type)
    eq_support=$(func_pipeline_parse_value "$idx" eq)

    case $type in
        "playback")
            cmd=aplay
            dummy_file=/dev/zero
        ;;
        "capture")
            cmd=arecord
            dummy_file=/dev/null
        ;;
    esac

    dlogi "eq_support= $eq_support"
    # if IIR/FIR filter is avilable, test with coef list
    for filter_type in iir fir; do
        if echo "$eq_support" | grep -q -i $filter_type; then
            func_test_filter $filter_type
        fi
    done

done

exit 0
