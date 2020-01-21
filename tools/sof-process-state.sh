#!/bin/bash

[[ $# -ne 1 ]] && echo "This script need parameter: pid/process-name to dump it's state" && builtin exit 2

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
# process not exist
[[ ! "$(ps $opt $process -o state --no-header)" ]] && \
    builtin echo "process: $process status: process run finished/not run" && builtin exit 2

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
