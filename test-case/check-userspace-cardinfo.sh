#!/bin/bash

##
## Case Name: check-userspace-cardinfo
## Preconditions:
##    N/A
## Description:
##    Get the card name from pactl info
##    check if there is an available card to do the following tests
## Case step:
##    1. run pactl to get the cards info
##    2. check the card name
## Expect result:
##    There is at least one available card for test
##

set -e

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

# check pulseaudio runs properly or not
func_lib_check_pa || die "Please check whether pulseaudio runs correctly or not"

func_opt_parse_option "$@"

OLDIFS=$IFS
dlogc "pactl list cards short"
cardlist=$(pactl list cards short)
: $((available_card=0))
IFS=$'\n'
for card in $cardlist; do
    # pactl list cards short format should be like:
    # 0	alsa_card.pci-0000_00_1f.3-platform-sof_sdw	module-alsa-card.c
    dlogi "found card: $(echo "$card" | awk '{print $2}')"
    echo "$card" |grep -i "usb" &>/dev/null || : $((available_card++))
done
IFS=$OLDIFS

if [ "$available_card" == "0" ]; then
    # TODO: do more check to give hint why there is no available card
    die "no available card for test"
fi
