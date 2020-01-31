#!/bin/bash

##
## Case Name: check-pause-resume-multi-mediaplayback-analog
## Preconditions:
##    N/A
## Description:
##    test playback with pause/resume on 2 separate simultaneous MediaPlayback
##      & Analog pipelines
##    fake pause/resume with expect
##    expect sleep for sleep time then mocks spacebar keypresses ' ' to
##    cause resume action
## Case step:
##    1. aplay on MediaPlayback pcm
##    2. aplay on Analog/i2s pcm
##    2. use expect to fake pause/resume in each pipeline
## Expect result:
##    no errors occur for either process
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['M']='pcm_MPb'      OPT_DESC_lst['M']='MediaPlayback pcm for playback. Example: hw:0,0'
OPT_PARM_lst['M']=1             OPT_VALUE_lst['M']=''

OPT_OPT_lst['A']='pcm_analog'   OPT_DESC_lst['A']='Analog pcm for playback. Example: hw:1,0'
OPT_PARM_lst['A']=1             OPT_VALUE_lst['A']=''

OPT_OPT_lst['l']='loop'     OPT_DESC_lst['l']='pause/resume repeat count'
OPT_PARM_lst['l']=1         OPT_VALUE_lst['l']=10

OPT_OPT_lst['i']='min'      OPT_DESC_lst['i']='random range min value, unit is ms'
OPT_PARM_lst['i']=1         OPT_VALUE_lst['i']='100'

OPT_OPT_lst['a']='max'      OPT_DESC_lst['a']='random range max value, unit is ms'
OPT_PARM_lst['a']=1         OPT_VALUE_lst['a']='200'

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

func_opt_parse_option $*

repeat_count=${OPT_VALUE_lst['l']}
#TODO: file name salt for capture
# configure random value range
rnd_min=${OPT_VALUE_lst['i']}
rnd_max=${OPT_VALUE_lst['a']}
rnd_range=$[ $rnd_max - $rnd_min ]
[[ $rnd_range -le 0 ]] && dlogw "Error random range scope [ min:$rnd_min - max:$rnd_max ]" && exit 2

cmd=aplay
dummy_file=/dev/zero
fmt="S16_LE"
channel=2
rate=48000

# MediaPlayback playback pcm settings
pcm_MPb=${OPT_VALUE_lst['M']}

# ANALOG playback pcm settings
pcm_ANALOG=${OPT_VALUE_lst['A']}

if [ "$pcm_MPb" = "" ]||[ "$pcm_ANALOG" = "" ];
then
    dloge "No playback pcms are specified. Skip the pause-resume test"
    exit 2
fi

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

func_lib_setup_kernel_last_line

dlogi "Entering HDMI playback expect script with: $cmd -D $pcm_MPb -r $rate -c $channel -f $fmt -vv -i $dummy_file -q"
dlogi "Entering ANALOG playback expect script with: $cmd -D $pcm_ANALOG -r $rate -c $channel -f $fmt -vv -i $dummy_file -q"

# expect is tcl language script
#   expr rand(): produces random numbers between 0 and 1
#   after ms: Ms must be an integer giving a time in milliseconds.
#       The command sleeps for ms milliseconds and then returns.
expect <<MEDIAPLAYBACK &
spawn $cmd -D $pcm_MPb -r $rate -c $channel -f $fmt -vv -i $dummy_file -q
set i 1
expect {
    "*#*+*\%" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) MPb: Wait for \$sleep_t ms before pause"
        send " "
        after \$sleep_t
        exp_continue
    }
    "*PAUSE*" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) MPb: Wait for \$sleep_t ms before resume"
        send " "
        after \$sleep_t
        incr i
        if { \$i > $repeat_count } { exit 0 }
        exp_continue
    }
}
exit 1
MEDIAPLAYBACK
expect <<ANALOG
spawn $cmd -D $pcm_ANALOG -r $rate -c $channel -f $fmt -vv -i $dummy_file -q
set i 1
expect {
    "*#*+*\%" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) ANALOG: Wait for \$sleep_t ms before pause"
        send " "
        after \$sleep_t
        exp_continue
    }
    "*PAUSE*" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) ANALOG: Wait for \$sleep_t ms before resume"
        send " "
        after \$sleep_t
        incr i
        if { \$i > $repeat_count } { exit 0 }
        exp_continue
    }
}
exit 1
ANALOG

ret=$?
#flush the output
echo

pkill aplay

sof-kernel-log-check.sh $KERNEL_LAST_LINE
exit $?
