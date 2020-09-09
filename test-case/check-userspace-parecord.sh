#!/bin/bash

##
## Case Name: check-userspace-parecord
## Preconditions:
##    N/A
## Description:
##    Go through all the sources and parecord on the sources whose
##    active port is available (jack connected) or unknown (DMIC)
## Case step:
##    1. go through all the sources
##    2. check the source's active port is available or not
##    3. parecord on the active port which is available or unknown
## Expect result:
##    parecord on the source successfully
##

set -e

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

# check pulseaudio runs properly or not
func_lib_check_pa || die "Please check whether pulseaudio runs correctly or not"

OPT_OPT_lst['r']='round'     OPT_DESC_lst['r']='round count'
OPT_PARM_lst['r']=1         OPT_VALUE_lst['r']=3

OPT_OPT_lst['d']='duration' OPT_DESC_lst['d']='parecord duration in second'
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

[[ -e $file ]] || { dlogw "$file does not exist, use /dev/zero as dummy playback source" && file=/dev/null; }

# TODO: check the parameter is valid or not

# go through all the sources
# get all the sources name
sourcekeys=$(pactlinfo.py --showsources)
for round in $(seq 1 $round_cnt); do
    for i in $sourcekeys; do
        sourcecard=$(pactlinfo.py --getsourcecardname "$i") || {
            dlogw "failed to get source $i card_name"
            continue
        }

        # Let's skip testing on USB card
        # TODO: add a list for other skipped cards such as HDA
        if echo "$sourcecard" |grep -i "usb" &>/dev/null; then
            continue
        fi

        sourceclass=$(pactlinfo.py --getsourcedeviceclass "$i") || {
            dlogw "failed to get source $i device class"
            continue
        }
        # Let's skip the monitor sources
        if echo "$sourceclass" |grep "monitor" &>/dev/null; then
            continue
        fi

        # get the source's active port
        actport=$(pactlinfo.py --getsourceactport "$i") || {
            dlogw "failed to get source $i active port"
            continue
        }
        # get the active port's information
        actportvalue=$(pactlinfo.py --getsourceportinfo "$actport") || {
            dlogw "failed to get source $i active port $actport info"
            continue
        }
        # check the active port is available or not from the port's information
        portavailable=$(echo "$actportvalue" |grep "not available") || true
        if [ -z "$portavailable" ]; then
            # now prepare to parecord on this source as the active port is not "not available"
            # get the source's name
            sourcename=$(pactlinfo.py --getsourcename "$i")
            sourcename=$(eval echo "$sourcename")
            dlogi "===== Testing: (Round: $round/$round_cnt) (source: $sourcename.$actport) ====="
            dlogc "parecord -v --device=$sourcename --raw --rate=$rate --format=$format --channels=$channel $file"
            parecord -v --device="$sourcename" --raw --rate=$rate --format=$format --channels=$channel $file &
            pid=$!
            sleep $duration
            # check whether process is still running
            count=$(ps -A| grep -c $pid) || true
            if [[ $count -eq 0 ]]; then
                if wait $pid; then #checks if process executed successfully or not
                    die "parecord has stopped successfully, which is abnormal"
                else
                    die "parecord on $sourcename failed (returned $?)"
                fi
            else
                dlogi "parecord runs successfully"
                # kill all parecord processes
                pkill -9 parecord >/dev/null
                sleep 0.5
            fi
        fi

    done
done
