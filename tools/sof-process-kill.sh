#!/bin/bash

cmd_lst=("aplay" "arecord")

for i in ${cmd_lst[@]}
do
    # Just kill UID to restrict process started by current user
    pkill -9 -U $UID $i
    echo "pkill $i with return $?"
done
sleep 1s
exit_code=0
# now check process status
for i in ${cmd_lst[@]}
do
    sof-process-state.sh $i
    if [[ $? -ne 0 ]]; then
        exit_code=1
    fi
done

builtin exit $exit_code
