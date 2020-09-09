#!/bin/bash

##
## Case Name: check-userspace-paplay
## Preconditions:
##    N/A
## Description:
##    Go through all the sinks and paplay on the sinks whose
##    active port is available (jack connected) or unknown (speaker)
## Case step:
##    1. go through all the sinks
##    2. check the sink's active port is available or not
##    3. paplay on the active port which is available or unknown
## Expect result:
##    paplay on the sinks successfully
##

set -e

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

# check pulseaudio runs properly or not
func_lib_check_pa || die "Please check whether pulseaudio runs correctly or not"

OPT_OPT_lst['r']='round'     OPT_DESC_lst['r']='round count'
OPT_PARM_lst['r']=1         OPT_VALUE_lst['r']=3

OPT_OPT_lst['d']='duration' OPT_DESC_lst['d']='paplay duration in second'
OPT_PARM_lst['d']=1         OPT_VALUE_lst['d']=8

OPT_OPT_lst['f']='file'   OPT_DESC_lst['f']='source file path'
OPT_PARM_lst['f']=1         OPT_VALUE_lst['f']='/dev/zero'

OPT_OPT_lst['F']='format'   OPT_DESC_lst['F']='sample format'
OPT_PARM_lst['F']=1         OPT_VALUE_lst['F']=s16le

OPT_OPT_lst['R']='rate'   OPT_DESC_lst['R']='sample rate'
OPT_PARM_lst['R']=1         OPT_VALUE_lst['R']=44100

OPT_OPT_lst['C']='channels'   OPT_DESC_lst['C']='channels'
OPT_PARM_lst['C']=1         OPT_VALUE_lst['C']=2

func_opt_parse_option "$@"

round_cnt=${OPT_VALUE_lst['r']}
duration=${OPT_VALUE_lst['d']}
file=${OPT_VALUE_lst['f']}
format=${OPT_VALUE_lst['F']}
rate=${OPT_VALUE_lst['R']}
channel=${OPT_VALUE_lst['C']}

[[ -e $file ]] || { dlogw "$file does not exist, use /dev/zero as dummy playback source" && file=/dev/zero; }

# TODO: check the parameter is valid or not

# go through all the sinks
# get all the sinks name
sinkkeys=$(pactlinfo.py --showsinks)
for round in $(seq 1 $round_cnt); do
    for i in $sinkkeys; do
        sinkcard=$(pactlinfo.py --getsinkcardname "$i") || {
            dlogw "failed to get sink $i card_name"
            continue
        }

        # Let's skip testing on USB card
        # TODO: add a list for other skipped cards such as HDA
        if echo "$sinkcard" |grep -q -i "usb"; then
            continue
        fi

        # get the sink's active port
        actport=$(pactlinfo.py --getsinkactport "$i") || {
            dlogw "failed to get sink $i active port"
            continue
        }

        # get the active port's information
        actportvalue=$(pactlinfo.py --getsinkportinfo "$actport") || {
            dlogw "failed to get sink $i active port $actport info"
            continue
        }

        # check the active port is available or not from the port's information
        portavailable=$(echo "$actportvalue" |grep "not available") || true
        if [ -z "$portavailable" ]; then
            # now prepare to paplay on this sink as the active port is not "not available"
            # get the sink's name
            sinkname=$(pactlinfo.py --getsinkname "$i")
            sinkname=$(eval echo "$sinkname")
            dlogi "===== Testing: (Round: $round/$round_cnt) (sink: $sinkname.$actport) ====="
            dlogc "paplay -v --device=$sinkname --raw --rate=$rate --format=$format --channels=$channel $file"
            paplay -v --device="$sinkname" --raw --rate=$rate --format=$format --channels=$channel $file &
            pid=$!
            sleep $duration
            # check whether process is still running
            count=$(ps -A| grep -c $pid) || true
            if [[ $count -eq 0 ]]; then
                if wait $pid; then #checks if process executed successfully or not
                    dlogi "paplay has stopped successfully"
                else
                    die "paplay on $sinkname failed (returned $?)"
                fi
            else
                dlogi "paplay runs successfully"
                # kill all paplay process
                kill -9 $pid
                sleep 0.5
            fi
        fi
    done
done
