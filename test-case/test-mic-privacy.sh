#!/bin/bash

##
## Case Name: test-mic-privacy
##
## Preconditions:
##    HW managed mode (Only for DMIC PCH and SNDW interfaces).
##    This test case requires physical loopback between playback and capture.
##    playback <=====> capture
##    USB relay switch is connected. The usbrelay app is installed.
##    Instruction: https://github.com/darrylb123/usbrelay
##
## Description:
##    Run alsabat process perform both playback and capture.
##    Enable MIC privacy.
##    Run alsabat process perform both playback and capture again.
##
## Case step:
##    1. Specify the pcm IDs for playback and capture
##    2. Check if usbrelay is installed and connected properly.
##    3. Run alsabat process perform both playback and capture.
##    4. Switch relay 1 to enable MIC privacy.
##    5. Run alsabat process perform both playback and capture.
##
## Expect result:
##    After step 3 the return value is 0.
##    After step 5 the return value is -1001 (no peak be detected).

# remove the existing alsabat wav files
rm -f /tmp/mc.wav.*

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['p']='pcm_p'     	OPT_DESC['p']='pcm for playback. Example: hw:0,0'
OPT_HAS_ARG['p']=1          	OPT_VAL['p']='hw:0,0'

OPT_NAME['N']='channel_p'       OPT_DESC['N']='channel number for playback.'
OPT_HAS_ARG['N']=1             OPT_VAL['N']='2'

OPT_NAME['c']='pcm_c'      	OPT_DESC['c']='pcm for capture. Example: hw:0,1'
OPT_HAS_ARG['c']=1             OPT_VAL['c']='hw:0,1'

OPT_NAME['C']='channel_c'       OPT_DESC['C']='channel number for capture.'
OPT_HAS_ARG['C']=1             OPT_VAL['C']='2'

OPT_NAME['s']='sof-logger'      OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

func_opt_parse_option "$@"
setup_kernel_check_point

pcm_p=${OPT_VAL['p']}
pcm_c=${OPT_VAL['c']}
channel_c=${OPT_VAL['C']}
channel_p=${OPT_VAL['N']}
rate=48000

dlogi "Params: pcm_p=$pcm_p, pcm_c=$pcm_c, channel_c=$channel_c, channel_p=$channel_p, rate=$rate, LOG_ROOT=$LOG_ROOT"

start_test

if [ "$pcm_p" = "" ]||[ "$pcm_c" = "" ]; then
	dloge "No playback or capture PCM is specified. Skip the alsabat test"
	exit 2
fi

# check if usbrelay tool is installed
if ! command -v usbrelay >/dev/null 2>&1; then
  dloge "usbrelay command not found. Please install usbrelay to control the mic privacy switch."
  exit 2
fi

check_locale_for_alsabat

# reset sof volume to 0dB
reset_sof_volume

# If MODEL is defined, set proper gain for the platform
if [ -z "$MODEL" ]; then
    # treat as warning only
    dlogw "NO MODEL is defined. Please define MODEL to run alsa_settings/MODEL.sh"
else
    dlogi "apply alsa settings for alsa_settings/MODEL.sh"
    set_alsa_settings "$MODEL"
fi

logger_disabled || func_lib_start_log_collect

function __upload_wav_file
{
    # upload the alsabat wav file
    for file in /tmp/mc.wav.*; do
        # alsabat has a bug where it creates an empty record in playback mode
        if test -s "$file"; then
            cp "$file" "$LOG_ROOT/"
        fi
    done
}

# check if usbrelay works and relays hardware is connected
if ! usbrelay_output=$(usbrelay 2>/dev/null) || [ -z "$usbrelay_output" ]; then
    dloge "usbrelay is not responding or no relays detected. Check hardware connection."
    exit 1
fi

dlogi "Turn off the mic privacy switch"
usbrelay HURTM_1=0
# wait for the mic privacy switch to be off
sleep 0.5

# check the PCMs before mic privacy test
dlogi "check the PCMs before mic privacy test"
aplay   -Dplug"$pcm_p" -d 1 /dev/zero -q || die "Failed to play on PCM: $pcm_p"
arecord -Dplug"$pcm_c" -d 1 /dev/null -q || die "Failed to capture on PCM: $pcm_c"

# Select the first card
first_card_name=$(aplay -l | awk '/^card ([0-9]+)/ {print $3; exit}')
# dump amixer contents always.
# Good case amixer settings is for reference, bad case for debugging.
amixer -c "${first_card_name}" contents > "$LOG_ROOT"/amixer_settings.txt

# check if capture and playback work
# BT offload PCMs also support mono playback.
dlogc "alsabat -P$pcm_p -C$pcm_c -c 2 -r $rate"
alsabat -P"$pcm_p" -C"$pcm_c" -c 2 -r $rate || {
    # upload failed wav file
    __upload_wav_file
    exit 1
}

dlogi "Turn on the mic privacy switch"
usbrelay HURTM_1=1
# wait for the mic privacy switch to be on
sleep 1

alsabat_output=$(mktemp)
dlogc "alsabat -P$pcm_p -C$pcm_c -c 2 -r $rate"
alsabat -P"$pcm_p" -C"$pcm_c" -c 2 -r $rate >"$alsabat_output" 2>&1
alsabat_status=$?

dlogi "Turn off the mic privacy switch."
usbrelay HURTM_1=0

if [ $alsabat_status -ne 0 ]; then
    if grep -q -e "Amplitude: 0.0; Percentage: \[0\]" -e "Return value is -1001" "$alsabat_output"
    then
        # Do nothing if signal is zero, this is expected
        # Return value is -1001
        dlogi "Alsabat output indicates zero signal as expected."
        :
    else
        dloge "alsabat failed with status $alsabat_status, but signal is not zero."
        __upload_wav_file
        dloge "alsabat output: $(cat "$alsabat_output")."
        exit 1
    fi
else
    dloge "alsabat passed, upload the wav files."
    dloge "alsabat output: $(cat "$alsabat_output")"
    exit 1
fi
rm -f "$alsabat_output"
