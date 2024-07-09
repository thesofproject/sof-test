#!/bin/bash

set -e

##
## Case Name: check-pause-resume
## Preconditions:
##    N/A
## Description:
##    playback/capture on each pipeline and feak pause/resume with expect
##    expect sleep for sleep time then mocks spacebar keypresses ' ' to
##    cause resume action
## Case step:
##    1. aplay/arecord on PCM
##    2. use expect to fake pause/resume
## Expect result:
##    no error happen for aplay/arecord
##

TOPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
# shellcheck source=case-lib/lib.sh
source "$TOPDIR"/case-lib/lib.sh

OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['m']='mode'     OPT_DESC['m']='test mode'
OPT_HAS_ARG['m']=1         OPT_VAL['m']='playback'

OPT_NAME['c']='count'    OPT_DESC['c']='pause/resume repeat count'
OPT_HAS_ARG['c']=1         OPT_VAL['c']=10

OPT_NAME['f']='file'     OPT_DESC['f']='file name'
OPT_HAS_ARG['f']=1         OPT_VAL['f']=''

OPT_NAME['i']='min'      OPT_DESC['i']='random range min value, unit is ms'
OPT_HAS_ARG['i']=1         OPT_VAL['i']='100'

OPT_NAME['a']='max'      OPT_DESC['a']='random range max value, unit is ms'
OPT_HAS_ARG['a']=1         OPT_VAL['a']='200'

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

OPT_NAME['S']='filter_string'   OPT_DESC['S']="run this case on specified pipelines"
OPT_HAS_ARG['S']=1             OPT_VAL['S']="id:any"

func_opt_parse_option "$@"
setup_kernel_check_point

tplg=${OPT_VAL['t']}
test_mode=${OPT_VAL['m']}
repeat_count=${OPT_VAL['c']}
#TODO: file name salt for capture
file_name=${OPT_VAL['f']}
# configure random value range
rnd_min=${OPT_VAL['i']}
rnd_max=${OPT_VAL['a']}

start_test

rnd_range=$(( rnd_max -  rnd_min ))
[[ $rnd_range -le 0 ]] && dlogw "Error random range scope [ min:$rnd_min - max:$rnd_max ]" && exit 2

case $test_mode in
    "playback")
        cmd=aplay
        cmd_opts="$SOF_APLAY_OPTS"
        dummy_file=/dev/zero
    ;;
    "capture")
        cmd=arecord
        cmd_opts="$SOF_ARECORD_OPTS"
        dummy_file=/dev/null
    ;;
    *)
        die "Invalid test mode: $test_mode (allow value : playback, capture)"
    ;;
esac

logger_disabled || func_lib_start_log_collect

[[ -z $file_name ]] && file_name=$dummy_file

func_pipeline_export "$tplg" "type:$test_mode & ${OPT_VAL['S']}"
for idx in $(seq 0 $((PIPELINE_COUNT - 1)))
do
    # set up checkpoint for each iteration
    setup_kernel_check_point
    channel=$(func_pipeline_parse_value "$idx" channel)
    rate=$(func_pipeline_parse_value "$idx" rate)
    fmt=$(func_pipeline_parse_value "$idx" fmt)
    dev=$(func_pipeline_parse_value "$idx" dev)
    snd=$(func_pipeline_parse_value "$idx" snd)

    # expect is tcl language script
    #   expr rand(): produces random numbers between 0 and 1
    #   after ms: Ms must be an integer giving a time in milliseconds.
    #       The command sleeps for ms milliseconds and then returns.
    dlogi "Entering expect script with:
      $cmd $SOF_ALSA_OPTS $cmd_opts -D $dev -r $rate -c $channel -f $fmt -vv -i $file_name -q"

    expect <<END
spawn $cmd $SOF_ALSA_OPTS $cmd_opts -D $dev -r $rate -c $channel -f $fmt -vv -i $file_name -q
set i 1
expect {
    "*#*+*\%" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) Wait for \$sleep_t ms before pause"
        send " "
        after \$sleep_t
        exp_continue
    }
    "*PAUSE*" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) Wait for \$sleep_t ms before resume"
        send " "
        after \$sleep_t
        incr i
        if { \$i > $repeat_count } { exit 0 }
        exp_continue
    }
}
exit 1
END
    ret=$?
    #flush the output
    echo
    if [ $ret -ne 0 ]; then
        func_lib_lsof_error_dump "$snd"
        sof-process-kill.sh ||
            dlogw "Kill process catch error"
        exit $ret
    fi
    # check kernel log for each iteration to catch issues
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" || die "Caught error in kernel log"
done
