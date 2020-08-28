#!/bin/bash

##
## Case Name: check-pause-release-suspend-resume
## Preconditions:
##    N/A
## Description:
##    test audio stream (playback or capture) with pause/release as well as suspend/resume
##    fake pause/release with expect on audio stream process
##    have system enter suspend state for 5 secs
##    resume from suspend state
##    release audio stream from paused state
##    repeat
## Case step:
##    1. audio stream process is started
##    2. audio stream process is then paused via mock spacebar press via expect
##    3. confirm audio stream is paused
##    4. have system enter suspend state for 5 secs
##    5. resume system from suspend state
##    6. release audio stream process from paused state
##    7. loop from #2 - #6
## Expect result:
##    no errors occur
##
##
## To run test manually:
## Preconditions
##     1. Device has ability to fully suspend.
##         - BYTs cannot enter necessary suspend state.
## Test Description
##     Check for errors during test cycle of:
##         playback -> pause -> suspend -> resume -> release cycles
##     * By changing aplay call to an arecord call, you can manual test capture
##       via the same method.
## Test Case:
##     1. Run in terminal 1:
##         aplay -Dhw:0,0 -fs16_le -c2 -r 48000 -vv -i /dev/zero
##     2. Press the spacebar to pause playback
##     3. Run in terminal 2:
##         sudo rtcwake -m mem -s 10
##     4. Device should suspend.
##     5. Once device has resumed, press spacebar in terminal 1 to release audio
##         playback from paused state.
##     6. Playback should resume normally.
##     7. Check journalctl -k for any unexpected errors.
##     8. Repeat as necessary.
## Expect result:
##  * aplay process should continue to be active after suspend / resume cycle.
##  * No unexpected errors should be present in journalctl -k during or after test
##      completion.

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

OPT_OPT_lst['m']='mode'         OPT_DESC_lst['m']='test mode. Example: playback; capture'
OPT_PARM_lst['m']=1             OPT_VALUE_lst['m']='playback'

OPT_OPT_lst['p']='pcm'          OPT_DESC_lst['p']='audio pcm. Example: hw:0,0'
OPT_PARM_lst['p']=1             OPT_VALUE_lst['p']='hw:0,0'

OPT_OPT_lst['f']='fmt'          OPT_DESC_lst['f']='audio format value'
OPT_PARM_lst['f']=1             OPT_VALUE_lst['f']='S16_LE'

OPT_OPT_lst['c']='channel'      OPT_DESC_lst['c']='audio channel count'
OPT_PARM_lst['c']=1             OPT_VALUE_lst['c']='2'

OPT_OPT_lst['r']='rate'         OPT_DESC_lst['r']='audio rate'
OPT_PARM_lst['r']=1             OPT_VALUE_lst['r']='48000'

OPT_OPT_lst['F']='file'         OPT_DESC_lst['F']='file name. Example: /dev/zero; /dev/null'
OPT_PARM_lst['F']=1             OPT_VALUE_lst['F']=''

OPT_OPT_lst['l']='loop'         OPT_DESC_lst['l']='loop count'
OPT_PARM_lst['l']=1             OPT_VALUE_lst['l']=5

OPT_OPT_lst['i']='sleep-period' OPT_DESC_lst['i']='sleep period of aplay, unit is ms'
OPT_PARM_lst['i']=1             OPT_VALUE_lst['i']='100'

OPT_OPT_lst['s']='sof-logger'   OPT_DESC_lst['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_PARM_lst['s']=0             OPT_VALUE_lst['s']=1

func_opt_parse_option "$@"

pcm=${OPT_VALUE_lst['p']}
fmt=${OPT_VALUE_lst['f']}
channel=${OPT_VALUE_lst['c']}
rate=${OPT_VALUE_lst['r']}
repeat_count=${OPT_VALUE_lst['l']}
sleep_period=${OPT_VALUE_lst['i']}
test_mode=${OPT_VALUE_lst['m']}
file_name=${OPT_VALUE_lst['F']}

case $test_mode in
    "playback")
        cmd=aplay
        dummy_file=/dev/zero
    ;;
    "capture")
        cmd=arecord
        dummy_file=/dev/null
    ;;
    *)
        die "Invalid test mode: $test_mode. Accepted test mode: playback; capture"
    ;;
esac

[[ -z $file_name ]] && file_name=$dummy_file


[[ ${OPT_VALUE_lst['s']} -eq 1 ]] && func_lib_start_log_collect

func_lib_setup_kernel_last_timestamp

dlogi "Entering audio stream expect script with: $cmd -D $pcm -r $rate -c $channel -f $fmt -vv -i $dummy_file -q"
dlogi "Will enter suspend-resume cycle during paused period of audio stream process"

rm -rf /tmp/sof-test.lock

# expect is tcl language script
#   catch: Evaluate script and trap exceptional returns
#   after ms: Ms must be an integer giving a time in milliseconds.
#       The command sleeps for ms milliseconds and then returns.
expect <<AUDIO
spawn $cmd -D $pcm -r $rate -c $channel -f $fmt -vv -i $dummy_file -q
set i 1
set sleep_t $sleep_period
expect {
    "#*+*\%" {
        #audio stream (aplay or arecord) is active now and playing
        puts "\r===== (\$i/$repeat_count) pb_pbm: Pause $cmd, then wait for ===== "
        puts "\r(\$i/$repeat_count) pb_pbm: $sleep_t ms after pause"
        send " "
        after \$sleep_t
        puts "Finished sleep. Confirming $cmd is paused."

        #check audio stream status --- R == paused, else == not paused
        set retval [catch { exec ps -C $cmd -o state --no-header } state]
        puts "$cmd state = \$state"

        if {[string equal \$state "R"] != 0} {
            puts "$cmd is paused, will now enter suspend-resume cycle"
        } else {
            puts "$cmd is not paused. Exiting test and failing."
            exit 1
        }

        #enter suspend-resume cycle once per pause instance
        set retval [catch { exec bash check-suspend-resume.sh -l 1 } msg]

        #prints logs from suspend-resume test
        puts \$msg
        puts "Finished suspend-resume test"
        if { \$retval } {
            puts "suspend resume cycle has failed."
            set error_code [lindex \$::errorCode {2}]
            puts "errorCode was: \$error_code"
            exit 1
        }

        #sucessful suspend/resume cycle, now release audio stream
        puts "\r(\$i/$repeat_count) pb_pbm: Release $cmd, then wait for"
        puts "\r(\$i/$repeat_count) pb_pbm: \$sleep_t ms after resume"
        send " "
        after \$sleep_t

        puts "Finished sleep after resume"
        incr i
        if { \$i > $repeat_count } { exit 0 }
        exp_continue
    }
}
AUDIO

ret=$?
#flush the output
echo
if [ $ret -ne 0 ]; then
    sof-process-kill.sh
    [[ $? -ne 0 ]] && dlogw "Kill process catch error"
    exit $ret
fi
sof-kernel-log-check.sh "$KERNEL_LAST_TIMESTAMP"
exit $?
