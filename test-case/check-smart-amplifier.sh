#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2020 Intel Corporation. All rights reserved.
set -e

##
## Case Name: check-smart-amplifier
## Preconditions:
##    require python3-numpy, python3-scipy and python3-matplotlib
##    to be installed, or wavetool.py will not work
## Description:
##    test smart amplifier with customized wavetool.py,
##    this tool will do binary comparison of reference wave file
##    and recorded wave file.
## Case step:
##    1. acquire playback & capture pipelines with smart_amp component
##    2. generate playback wave file (default 997Hz sine wave)
##    3. play reference wave file through smart_amp playback pipeline
##       and record it back through smart_amp capture pipeline
##    4. compare channel 0/1, 2/3 of recorded wave with reference wave
## Expect result:
##    1. reference wave and recorded wave are binary same
##    2. delay in recorded wave less than 5ms
##

# source from the relative path of current folder
# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

# What we want here is the "$TPLG" string
# shellcheck disable=SC2016
OPT_OPT_lst['t']='tplg'     OPT_DESC_lst['t']='tplg file, default value is env TPLG: $TPLG'
# $TPLG is assigned outside this script as env variable
# shellcheck disable=SC2153
OPT_PARM_lst['t']=1         OPT_VALUE_lst['t']="$TPLG"

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=1

OPT_OPT_lst['d']='duration' OPT_DESC_lst['d']='playback/capture duration in second'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=6

# We need OPT_OPT_lst to tell what the command option is, and OPT_PARM_lst to tell
# how many arguments this option required, though they are not used.
# shellcheck disable=SC2034
OPT_OPT_lst['F']='fmts'   OPT_DESC_lst['F']='Iterate all supported formats'
# shellcheck disable=SC2034
OPT_PARM_lst['F']=0         OPT_VALUE_lst['F']=0

func_opt_parse_option "$@"

duration=${OPT_VALUE_lst['d']}
loop_cnt=${OPT_VALUE_lst['l']}
tplg=${OPT_VALUE_lst['t']}

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

func_pipeline_export $tplg "smart_amp:any"
func_lib_setup_kernel_last_line

[ "$PIPELINE_COUNT" == "2" ] || die "Only detect $PIPELINE_COUNT pipeline(s) from topology, but two are needed"

for idx in $(seq 0 $((PIPELINE_COUNT - 1)))
do
    type=$(func_pipeline_parse_value "$idx" type)
    if [ "$type" == "playback" ]; then
        pb_chan=$(func_pipeline_parse_value "$idx" ch_max)
        pb_rate=$(func_pipeline_parse_value "$idx" rate)
        pb_dev=$(func_pipeline_parse_value "$idx" dev)
    else
        cp_chan=$(func_pipeline_parse_value "$idx" ch_max)
        cp_rate=$(func_pipeline_parse_value "$idx" rate)
        cp_fmt=$(func_pipeline_parse_value "$idx" fmt)
        cp_fmts=$(func_pipeline_parse_value "$idx" fmts)
        cp_dev=$(func_pipeline_parse_value "$idx" dev)
    fi
done

fmts="$cp_fmt"
if [ ${OPT_VALUE_lst['F']} = '1' ]; then
    fmts="$cp_fmts"
fi

for i in $(seq 1 $loop_cnt)
do
    for fmt in $fmts
    do
        dlogi "Testing: iteration $i of $loop_cnt with $fmt format"
        # S24_LE format is not supported
        if [ "$fmt" == "S24_LE" ]; then
            continue
        fi
        # generate wave file
        tmp_dir="/tmp"
        file="$tmp_dir/tmp_wave_${fmt%_*}.wav"
        recorded_file="$tmp_dir/recorded_tmp_wave_${fmt%_*}.wav"
        wavetool.py -gsine -A0.8 -B"${fmt%_*}" -o"$file"
        dlogc "aplay -D$pb_dev -r $pb_rate -c $pb_chan -f $fmt -d $duration -q $file &"
        aplay -D"$pb_dev" -r "$pb_rate" -c "$pb_chan" -f "$fmt" -d "$duration" -v -q "$file" &
        dlogc "arecord -D$cp_dev -r $cp_rate -c $cp_chan -f $fmt -d $duration -q $recorded_file"
        arecord -D"$cp_dev" -r "$cp_rate" -c "$cp_chan" -f "$fmt" -d "$duration" -v -q "$recorded_file"
        dlogi "Comparing recorded wave and reference wave"
        wavetool.py -a"smart_amp" -R"$recorded_file" || die "wavetool.py exit with $?"
        # clean up generated wave files
        rm -rf "$file" "$recorded_file"
        sleep 2
    done
done

sof-kernel-log-check.sh "$KERNEL_LAST_LINE"
