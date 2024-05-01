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

OPT_NAME['r']='round'      OPT_DESC['r']='round count'
OPT_HAS_ARG['r']=1         OPT_VAL['r']=3

OPT_NAME['d']='duration'   OPT_DESC['d']='parecord duration in second'
OPT_HAS_ARG['d']=1         OPT_VAL['d']=8

OPT_NAME['f']='file'       OPT_DESC['f']='source file path'
OPT_HAS_ARG['f']=1         OPT_VAL['f']='/dev/zero'

OPT_NAME['F']='format'     OPT_DESC['F']='sample format'
OPT_HAS_ARG['F']=1         OPT_VAL['F']=s16le

OPT_NAME['R']='rate'       OPT_DESC['R']='sample rate'
OPT_HAS_ARG['R']=1         OPT_VAL['R']=44100

OPT_NAME['C']='channels'   OPT_DESC['C']='channels'
OPT_HAS_ARG['C']=1         OPT_VAL['C']=2

func_opt_parse_option "$@"
setup_kernel_check_point

round_cnt=${OPT_VAL['r']}
duration=${OPT_VAL['d']}
file=${OPT_VAL['f']}
format=${OPT_VAL['F']}
rate=${OPT_VAL['R']}
channel=${OPT_VAL['C']}

start_test

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
        if echo "$sourcecard" |grep -q -i "usb"; then
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
                kill -9 $pid
                sleep 0.5
            fi
        fi

    done
done
