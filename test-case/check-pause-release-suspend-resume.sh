#!/bin/bash

set -e

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
##     7. Check dmesg for any unexpected errors.
##     8. Repeat as necessary.
## Expect result:
##  * aplay process should continue to be active after suspend / resume cycle.
##  * No unexpected errors should be present in dmesg during or after test
##      completion.

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

CASEDIR=$(dirname "${BASH_SOURCE[0]}")

OPT_NAME['m']='mode'             OPT_DESC['m']='test mode. Example: playback; capture'
OPT_HAS_ARG['m']=1               OPT_VAL['m']='playback'

OPT_NAME['F']='file'             OPT_DESC['F']='file name. Example: /dev/zero; /dev/null'
OPT_HAS_ARG['F']=1               OPT_VAL['F']=''

OPT_NAME['l']='loop'             OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1               OPT_VAL['l']=5

OPT_NAME['i']='interval'         OPT_DESC['i']='interval before checking the aplay/arecord status after pause/release'
OPT_HAS_ARG['i']=1               OPT_VAL['i']='500'

OPT_NAME['s']='sof-logger'       OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0               OPT_VAL['s']=1

OPT_NAME['t']='tplg'             OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1               OPT_VAL['t']="$TPLG"

OPT_NAME['P']='filter_string'    OPT_DESC['P']='run this case on specified pipelines'
OPT_HAS_ARG['P']=1               OPT_VAL['P']='id:any'

OPT_NAME['T']='type'             OPT_DESC['T']="specify the sleep type for suspend/resume:s2idle/deep"
OPT_HAS_ARG['T']=1               OPT_VAL['T']=""

func_opt_parse_option "$@"

repeat_count=${OPT_VAL['l']}
interval=${OPT_VAL['i']}
test_mode=${OPT_VAL['m']}
file_name=${OPT_VAL['F']}
tplg=${OPT_VAL['t']}

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

# only run suspend/resume once for each loop.
# Use system default value if no sleep type is specified
sleep_opts="-l 1"
[ -z "${OPT_VAL['T']}" ] || sleep_opts+=" -T ${OPT_VAL['T']}"

[[ -z $file_name ]] && file_name=$dummy_file


logger_disabled || func_lib_start_log_collect

setup_kernel_check_point

func_pipeline_export "$tplg" "type:$test_mode & ${OPT_VAL['P']}"

for idx in $(seq 0 $((PIPELINE_COUNT - 1)))
do
    channel=$(func_pipeline_parse_value "$idx" channel)
    rate=$(func_pipeline_parse_value "$idx" rate)
    fmt=$(func_pipeline_parse_value "$idx" fmt)
    dev=$(func_pipeline_parse_value "$idx" dev)

    dlogi "Entering audio stream expect script with: $cmd -D $dev -r $rate -c $channel -f $fmt -vv -i $file_name -q"
    dlogi "Will enter suspend-resume cycle during paused period of audio stream process"

    # expect is tcl language script
    # catch: Evaluate script and trap exceptional returns
    # after ms: Ms must be an integer giving a time in milliseconds.
    # The command sleeps for ms milliseconds and then returns.
    expect <<AUDIO
    spawn $cmd -D $dev -r $rate -c $channel -f $fmt -vv -i $file_name -q
    set i 1
    expect {
        "#*+*\%" {
            # audio stream (aplay or arecord) is active now and playing
            puts "\r===== (\$i/$repeat_count) pb_pbm: Pause $cmd, then wait for ===== "
            puts "\r(\$i/$repeat_count) pb_pbm: $interval ms after pause"
            send " "
            after $interval
            puts "Finished sleep. Confirming $cmd is paused."
            # check audio stream status --- R == paused, else == not paused
            set retval [catch { exec ps -C $cmd -o state --no-header } state]
            puts "$cmd state = \$state"
            if {[string equal \$state "R"] != 0} {
                puts "$cmd is paused, will now enter suspend-resume cycle"
            } else {
                puts "$cmd is not paused. Exiting test and failing."
                exit 1
            }
            # enter suspend-resume cycle once per pause instance
            set retval [catch { exec bash $CASEDIR/check-suspend-resume.sh $sleep_opts } msg]
            # prints logs from suspend-resume test
            puts \$msg
            puts "Finished suspend-resume test"
            if { \$retval } {
                puts "suspend resume cycle has failed."
                set error_code [lindex \$::errorCode {2}]
                puts "errorCode was: \$error_code"
                exit 1
            }
            # sucessful suspend/resume cycle, now release audio stream
            puts "\r(\$i/$repeat_count) pb_pbm: Release $cmd, then wait for"
            puts "\r(\$i/$repeat_count) pb_pbm: $interval ms after resume"
            send " "
            after $interval
            puts "Finished sleep after resume"
            incr i
            if { \$i > $repeat_count } { exit 0 }
            exp_continue
        }
    }
AUDIO

    if [ "$?" -ne 0 ]; then
        sof-process-kill.sh || dlogw "Kill process catch error"
        exit 1
    fi
done

sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" || die "Caught error in kernel log"
