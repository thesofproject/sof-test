#!/bin/bash

##
## Case Name: check-pause-resume-simultaneous-playback-capture
## Preconditions:
##    N/A
## Description:
##    playback and capture on separate pipelines and fake pause/resume with expect
##    expect sleep for sleep time then mocks spacebar keypresses ' ' to
##    cause resume action
## Case step:
##    1. aplay on PCM
##    2. arecord on PCM
##    2. use expect to fake pause/resume in each pipeline
## Expect result:
##    no errors occur for either process
##

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['p']='pcm_p'        OPT_DESC_lst['p']='pcm for playback. Example: hw:0,0'
OPT_PARM_lst['p']=1             OPT_VALUE_lst['p']=''

OPT_OPT_lst['c']='pcm_c'        OPT_DESC_lst['c']='pcm for capture. Example: hw:1,0'
OPT_PARM_lst['c']=1             OPT_VALUE_lst['c']=''

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

# playback pcm settings
pcm_p=${OPT_VALUE_lst['p']}
pcm_p_cmd=aplay
pcm_p_dummy_file=/dev/zero

# capture pcm settings
pcm_c=${OPT_VALUE_lst['c']}
pcm_c_cmd=arecord
pcm_c_dummy_file=/dev/null

channel=2
rate=48000
fmt="S16_LE"

if [ "$pcm_p" = "" ]||[ "$pcm_c" = "" ];
then
    dloge "No playback or capture PCM is specified. Skip the pause-resume test"
    exit 2
fi

[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

func_lib_setup_kernel_last_line

dlogi "Entering playback expect script with: $pcm_p_cmd -D $pcm_p -r $rate -c $channel -f $fmt -vv -i $pcm_p_dummy_file -q"
dlogi "Entering capture expect script with: $pcm_c_cmd -D $pcm_c -r $rate -c $channel -f $fmt -vv -i $pcm_c_dummy_file -q"

# expect is tcl language script
#   expr rand(): produces random numbers between 0 and 1
#   after ms: Ms must be an integer giving a time in milliseconds.
#       The command sleeps for ms milliseconds and then returns.
expect <<PLAYBACK &
spawn $pcm_p_cmd -D $pcm_p -r $rate -c $channel -f $fmt -vv -i $pcm_p_dummy_file -q
set i 1
expect {
    "*#*+*\%" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) PB: Wait for \$sleep_t ms before pause"
        send " "
        after \$sleep_t
        exp_continue
    }
    "*PAUSE*" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) PB: Wait for \$sleep_t ms before resume"
        send " "
        after \$sleep_t
        incr i
        if { \$i > $repeat_count } { exit 0 }
        exp_continue
    }
}
exit 1
PLAYBACK
expect <<CAPTURE
spawn $pcm_c_cmd -D $pcm_c -r $rate -c $channel -f $fmt -vv -i $pcm_c_dummy_file -q
set i 1
expect {
    "*#*+*\%" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) CP: Wait for \$sleep_t ms before pause"
        send " "
        after \$sleep_t
        exp_continue
    }
    "*PAUSE*" {
        set sleep_t [expr int([expr rand() * $rnd_range]) + $rnd_min ]
        puts "\r(\$i/$repeat_count) CP: Wait for \$sleep_t ms before resume"
        send " "
        after \$sleep_t
        incr i
        if { \$i > $repeat_count } { exit 0 }
        exp_continue
    }
}
exit 1
CAPTURE

ret=$?
#flush the output
echo

pkill aplay
pkill arecord

sof-kernel-log-check.sh $KERNEL_LAST_LINE
exit $?
