#!/bin/bash

set -e

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
# shellcheck source=case-lib/lib.sh
source "$my_dir"/../case-lib/lib.sh

OPT_NAME['t']='tplg'     OPT_DESC['t']="tplg file, default value is env TPLG: $TPLG"
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['d']='duration' OPT_DESC['d']='aplay duration in second'
OPT_HAS_ARG['d']=1         OPT_VAL['d']=1

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=1

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

func_opt_parse_option "$@"
tplg=${OPT_VAL['t']}
duration=${OPT_VAL['d']}
loop_cnt=${OPT_VAL['l']}

# import only EQ pipeline from topology
func_pipeline_export "$tplg" "eq:any"
sofcard=${SOFCARD:-0}

start_test
setup_kernel_check_point

# Test equalizer
func_test_eq()
{
    local id=$1
    local conf=$2
    local double_quoted_id=\""$id"\"

    dlogc "sof-ctl -Dhw:$sofcard -c name=$double_quoted_id -s $conf"
    sof-ctl -Dhw:"$sofcard" -c name="$double_quoted_id" -s "$conf" || {
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
# param1 must be must be component name
func_test_filter()
{
    local testfilter=$1
    dlogi "Get amixer control id for $testfilter"
    Filterid=$("$my_dir"/../tools/topo_effect_kcontrols.py "$tplg" "$testfilter")
    if [ -z "$Filterid" ]; then
        die "can't find $testfilter"
    fi

    if is_ipc4; then
        ipc_dir="ipc4"
    else
        ipc_dir="ipc3"
    fi

    if [[ ${Filterid^^} == *"IIR"* ]]; then
        comp_dir="eq_iir"
    elif [[ ${Filterid^^} == *"FIR"* ]]; then
        comp_dir="eq_fir"
    else
        die "Not supported control: $Filterid"
    fi

    nFilterList=$(find "${my_dir}/eqctl/$ipc_dir/$comp_dir/" -name '*.txt' | wc -l)
    dlogi "$testfilter list, num= $nFilterList"
    if [ "$nFilterList" -eq  0 ]; then
        die "$testfilter flter coeff list error!"
    fi

    for i in $(seq 1 "$loop_cnt")
    do
        dlogi "===== [$i/$loop_cnt] Test $testfilter config list, $testfilter amixer control id=$Filterid ====="
        for config in "${my_dir}/eqctl/$ipc_dir/$comp_dir"/*.txt; do
            func_test_eq "$Filterid" "$config" || {
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
    IFS=" " read -r -a eq_support <<< "$(func_pipeline_parse_value "$idx" eq)"

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

    dlogi "eq_support= ${eq_support[*]}"
    # if IIR/FIR filter is avilable, test with coef list
    for comp_id in "${eq_support[@]}"; do
        func_test_filter "$comp_id"
    done

done

sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
