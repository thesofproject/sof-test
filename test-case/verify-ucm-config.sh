#!/bin/bash

##
## Case Name: verify-ucm-config
## Preconditions:
##    N/A
## Description:
##    verify the ucm configuration
## Case step:
##    1. load the ucm config file
##    2. check ucm can be run by alsaucm correctly or not:
##       check the ucm configuration file meets the syntax or not
##       check if the devices can be enabled or not
##       check if the controls can be set correctly or not
##       and so on. Details can be found in cmd 'alsaucm --help'
## Expect result:
##    command line check with $? without error
## Example of alsaucm output of verbs:
##   0: HiFi
##    Play HiFi quality Music.
## Example of alsaucm output of devices:
##   0: Speaker
##     description of Speaker.

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

func_opt_parse_option "$@"
setup_kernel_check_point

start_test

setup_alsa

declare -A verb_array

# get the cards all verbs. The verbs are the items of SectionUseCase in
# UCM config file.
# For example, There is:
#  SectionUseCase."HiFi" {
#      File "HiFi.conf"
#      Comment "Play HiFi Music"
#  }
# Then we will get the below information after we run `alsaucm -c "$cardname" list _verbs`
#   0: HiFi
#    Play HiFi quality Music.
func_get_verbs()
{
    dlogc "alsaucm -c '$cardname' list _verbs"
    verbs=`alsaucm -c "$cardname" list _verbs 2>/dev/null`
    [[ $? -ne 0 ]] && die "'$cardname' list _verbs failed!"
    [[ -z "$verbs" ]] && die "'$cardname' ucm has no verbs!"

    # save the verbs into array verb_array
    local OLD_IFS="$IFS"
    IFS=$'\n'
    ((verbs_desc_line=0))

    # verb counter
    ((verb_i=0))
    # $desc_line is used to define it is the even line (description line) or the odd line
    # verb format: there are 2 lines in each verb.
    # The first line  is the verb's identifier;
    # The second line is the verb's descriptor
    # For example, run `alsaucm -c cardname list _verbs` and suppose we get:
    #   0: HiFi
    #    Play HiFi quality Music.
    # the verb is 'HiFi'
    # the verb's description is "Play HiFi quality Music"
    for verb in $verbs; do
	if [ $verbs_desc_line -eq 0 ]; then
	    # get the verb identifier. In the upper example, it is "HiFi"
	    verb=`echo $verb|awk '{print $2}'`
            [[ -z "$verb" ]] && dlogw "verb is null, skipping" && continue
            dlogi "found verb: $verb"
	    verb_array[$verb_i]="$verb"
	    ((verb_i++))
	    ((verbs_desc_line=1))
	else
            # Let's skip the description
	    ((verbs_desc_line=0))
	fi
    done
    IFS="$OLD_IFS"
}

func_verify_verb_device()
{
    local cardname=$1
    local verb=$2
    local -A dev_array

    # 1. get all the devices used by the verb

    # The device is defined in "SectionDevice". For example:
    #  SectionDevice."Speaker" {
    #      xxxx
    #  }
    # Then the device is "Speaker"
    dlogc "alsaucm -c '$cardname' set _verb $verb list _devices"
    devices=$(alsaucm -c "$cardname" set _verb $verb list _devices 2>/dev/null)
    [[ $? -ne 0 ]] && dloge "list device failed" && return 1

    local OLD_IFS="$IFS"
    IFS=$'\n'
    ((devs_desc_line=0))

    # 2. save the devices into the array dev_array

    # device counter
    ((device_i=0))
    # After run $(alsaucm -c "$cardname" set _verb $verb list _devices),
    # it will show all the devices it supports. Each device takes 2 lines output.
    # The first line is the device identifier;
    # The second line is the device description.
    # For example:
    #   0: Speaker
    #     description of Speaker.

    for device in $devices; do
	if [ $devs_desc_line -eq "0" ]; then
	    device=`echo $device |awk -F ": " '{print $2}'`
            [[ -z "$verb" ]] && dlogw "device is null, skipping" && continue
            dlogi "found device: $device"
	    dev_array[$device_i]="$device"
	    ((device_i++))
            ((devs_desc_line=1))
        else
            # Let's skip the description
            ((devs_desc_line=0))
        fi
    done
    IFS="$OLD_IFS"

    # 3. alsaucm test on the devices
    for device in "${dev_array[@]}"; do
	    # 3.1 enable the device and check if the device is really enabled or not
            dlogc "alsaucm -c '$cardname' set _verb '$verb' set _enadev '$device' list1 _enadevs"
            ret=`alsaucm -c "$cardname" set _verb "$verb" set _enadev "$device" list1 _enadevs 2>/dev/null`
            [[ $? -ne 0 ]] && dloge "enable '$verb':'$device' failed" && return 1
            ret=`echo $ret |grep "$device" 2>/dev/null`
            [[ -z "$ret" ]] && dloge "'$verb':'$device' is not in the enabled device list" && return 1

	    # 3.2 enable the device and setup the controls to check if the controls can be set correctly or not
            dlogc "alsaucm -c '$cardname' set _verb '$verb' set _enadev '$device' reload"
            alsaucm -c "$cardname" set _verb "$verb" set _enadev "$device" reload 2>/dev/null
            [[ $? -ne 0 ]] && dloge "reload '$verb':'$device' setting failed!" && return 1
    done

    return 0
}

sofcard=${SOFCARD:-0}
cardname=$(sof-dump-status.py -s $sofcard)
[[ $? -ne 0 ]] && exit 1

# 1. use alsaucm to open the card
dlogc "alsaucm -c ${cardname} open ${cardname}"
alsaucm -c "${cardname}" open "${cardname}" 2>/dev/null
[[ $? -ne 0 ]] && die "open card '$cardname' failed!"

# 2. try to reload the card to the initial settings.
# These setting is defined in 'SectionDefaults' in UCM config file.
dlogc "alsaucm -c "$cardname" reload"
alsaucm -c "$cardname" reload 2>/dev/null
[[ $? -ne 0 ]] && die "card '$cardname' reload failed."

# 3. get all the verbs
func_get_verbs

# 4. go through the verbs test
for verb in "${verb_array[@]}"; do
	# 4.1 test setting verb works or not. In the upper example, it means to use 'HiFi' use case.
        dlogc "alsaucm -c '$cardname' set _verb $verb get _verb"
        ret=`alsaucm -c "$cardname" set _verb "$verb" get _verb 2>/dev/null`
        [[ $? -ne 0 ]] && die "set verb: $verb failed!"
        ret=`echo $ret |grep "$verb" 2>/dev/null`
        [[ -z "$ret" ]] && die "'$verb' is not the selected verb"

	# 4.2 Let's go through all the devices supported in the verb, e.g. "HiFi" use case.
        func_verify_verb_device "$cardname" "$verb"
        ret=$?
        [[ $ret -ne 0 ]] && exit $ret
done

exit 0
