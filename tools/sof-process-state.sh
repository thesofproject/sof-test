#!/bin/bash

# This script uses ps to inspect the state of either:
#
# - a single process specified by its PID number, or
# - all running instances of a given command like "aplay" or "arecord"
#
# Exit status
# 0  if at least one process was found and they're _all_ OK
# 1  if at least one process was found at least one of them is abnormal
# 2  if no process match, or
#       wrong number of arguments given

[[ $# -ne 1 ]] && >&2 echo "This script needs parameter: pid/process-name to dump its state" && builtin exit 2

# catch from man ps: PROCESS STATE CODES
declare -A PS_STATUS
PS_STATUS['D']='uninterruptible sleep (usually IO)'
PS_STATUS['R']='running or runnable (on run queue)'
PS_STATUS['S']='interruptible sleep (waiting for an event to complete)'
PS_STATUS['T']='stopped by job control signal'
PS_STATUS['t']='stopped by debugger during the tracing'
PS_STATUS['W']='paging (not valid since the 2.6.xx kernel)'
PS_STATUS['X']='dead (should never be seen)'
PS_STATUS['Z']='defunct ("zombie") process, terminated but not reaped by its parent'

process=$1
# have value which is not the number
[[ "${process//[0-9]/}" ]] && opt="-C" || opt="-p"
exit_code=1
# process does not exist
[[ ! "$(ps $opt $process -o state --no-header)" ]] && \
    >&2 builtin echo "process: $process, status: not found" && builtin exit 2

abnormal_status=0
# process status detect
for state in $(ps $opt $process -o state --no-header)
do
    abnormal_status=$[ $abnormal_status + 1 ]
    # aplay prepare: 'D'; aplay playing: 'S'; aplay pause: 'R';
    [[ "$state" == 'D' || "$state" == 'S' || "$state" == 'R' ]] && abnormal_status=$[ $abnormal_status - 1 ]
    builtin echo process: $process status: ${PS_STATUS[$state]}
done

[[ $abnormal_status -eq 0 ]] && builtin exit 0
builtin exit 1
