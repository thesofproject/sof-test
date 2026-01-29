#!/bin/bash

##
## Case Name: check alsabat
##
## Preconditions:
##    This test case requires physical loopback between playback and capture.
##    playback <=====>  capture
##    nocodec : no need to use hw loopback cable, It support DSP loopback by quirk
##
## Description:
##    Run two alsabat instances concurrently, one on each specified PCM: playback
##    and capture.
##
##    Warning: as of January 2024, "man alsabat" is incomplete and
##    documents only the "single instance" mode where a single alsabat
##    process performs both playback and capture.
##
## Case step:
##    1. Specify the pcm IDs for playback and catpure
##    3. run alsabat test
##
## Expect result:
##    The return value of alsabat is 0
##

# remove the existing alsabat wav files
rm -f /tmp/bat.wav.*

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['p']='pcm_p'     	OPT_DESC['p']='pcm for playback. Example: hw:0,0'
OPT_HAS_ARG['p']=1          	OPT_VAL['p']=''

OPT_NAME['C']='channel_c'       OPT_DESC['C']='channel number for capture.'
OPT_HAS_ARG['C']=1             OPT_VAL['C']='1'

OPT_NAME['N']='channel_p'       OPT_DESC['N']='channel number for playback.'
OPT_HAS_ARG['N']=1             OPT_VAL['N']='2'

OPT_NAME['r']='rate'            OPT_DESC['r']='sample rate'
OPT_HAS_ARG['r']=1             OPT_VAL['r']=48000

OPT_NAME['c']='pcm_c'      	OPT_DESC['c']='pcm for capture. Example: hw:1,0'
OPT_HAS_ARG['c']=1             OPT_VAL['c']=''

OPT_NAME['f']='format'       OPT_DESC['f']='target format'
OPT_HAS_ARG['f']=1             OPT_VAL['f']="S16_LE"

OPT_NAME['F']='frequency'       OPT_DESC['F']='target frequency'
OPT_HAS_ARG['F']=1             OPT_VAL['F']=821

OPT_NAME['k']='sigmak'		OPT_DESC['k']='sigma k value'
OPT_HAS_ARG['k']=1             OPT_VAL['k']=2.1

OPT_NAME['n']='frames'          OPT_DESC['n']='test frames'
OPT_HAS_ARG['n']=1             OPT_VAL['n']=240000

OPT_NAME['s']='sof-logger'      OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

func_opt_parse_option "$@"
setup_kernel_check_point

pcm_p=${OPT_VAL['p']}
pcm_c=${OPT_VAL['c']}
rate=${OPT_VAL['r']}
channel_c=${OPT_VAL['C']}
channel_p=${OPT_VAL['N']}
format=${OPT_VAL['f']}
frequency=${OPT_VAL['F']}
sigmak=${OPT_VAL['k']}
frames=${OPT_VAL['n']}

start_test

if [ "$pcm_p" = "" ]||[ "$pcm_c" = "" ];
then
	dloge "No playback or capture PCM is specified. Skip the alsabat test"
	exit 2
fi

# Check device for AudioPlug Loopback enabled or not for LNL HDA
if [ "$AUDIOPLUG_LOOPBACK" == "true" ] && [ "$MODEL" == "LNLM_RVP_HDA" ]; then

	dlogi "The Device have AUDIO PLUG LOOPBACK enabled for LNLM_RVP_HDA"

	# Check for playback/capture used USB codec, if yes replace with headset device
        if [ "$pcm_c" == "hw:CODEC,0" ]; then
	    pcm_c="hw:sofhdadsp,0"
	    dlogi "Capture device changed to $pcm_c"
        else
	    pcm_p="hw:sofhdadsp,0"
	    dlogi "Playback device changed to $pcm_p"
	fi
fi

# Check device for AudioPlug Loopback enabled or not for LNL SDW
if [ "$AUDIOPLUG_LOOPBACK" == "true" ] && [ "$MODEL" == "LNLM_SDW_AIOC" ]; then

	dlogi "The Device have AUDIO PLUG LOOPBACK enabled for LNLM_SDW_AIOC"

        # Check for playback/capture used USB codec, if yes replace with headset device
        if [ "$pcm_c" == "hw:CODEC,0" ]; then
	    pcm_c="hw:sofsoundwire,1"
	    dlogi "Capture device changed to $pcm_c"
        else
	    pcm_p="hw:sofsoundwire,0"
	    dlogi "Playback device changed to $pcm_p"
        fi
fi


check_locale_for_alsabat

logger_disabled || func_lib_start_log_collect

set_alsa

function __upload_wav_file
{
    # upload the alsabat wav file
    for file in /tmp/bat.wav.*
    do
	# alsabat has a bug where it creates an empty record in playback
	# mode
	if test -s "$file"; then
	    cp "$file" "$LOG_ROOT/"
	fi
    done
}

# Set default pipewire sink and source
set_pcms_in_pipewire()
{
    set_default_pipewire_sink_for_alsa_pcm "$pcm_p"
    set_default_pipewire_source_for_alsa_pcm "$pcm_c"
}

check_the_pcms()
{
    aplay   "-Dplug${pcm_p}" -d 1 /dev/zero -q || die "Failed to play on PCM: ${pcm_p}"
    arecord "-Dplug${pcm_c}" -d 1 /dev/null -q || die "Failed to capture on PCM: ${pcm_c}"
}

check_the_pcms_with_pipewire()
{
    aplay   -D pipewire -d 1 /dev/zero -q || die "Failed to play on pipewire"
    arecord -D pipewire -d 1 /dev/null -q || die "Failed to capture on pipewire"
}

run_test_on_pipewire()
{
    # Set correct sink and source in pipewire
    set_pcms_in_pipewire

    # check the PCMs before alsabat test
    check_the_pcms_with_pipewire

    # alsabat tests
    dlogc "alsabat -P pipewire --standalone -n $frames -r $rate -c $channel_p -f $format -F $frequency -k $sigmak"
    alsabat -P pipewire --standalone -n "${frames}" -c "${channel_p}" -r "${rate}" -f "${format}" -F "${frequency}" -k "${sigmak}" & playPID=$!

    dlogc "alsabat -C pipewire --standalone -n $frames -c $channel_p -r $rate -f $format -F $frequency -k $sigmak"
    alsabat -C pipewire --standalone -n "${frames}" -c "${channel_p}" -r "${rate}" -f "${format}" -F "${frequency}" -k "${sigmak}" || {
            # upload failed wav file
            __upload_wav_file
            exit 1
    }
}

run_test_on_alsa_direct_mode()
{
    # check the PCMs before alsabat test
    check_the_pcms

    # alsabat test
    # BT offload PCMs also support mono playback.
    dlogc "alsabat -P$pcm_p --standalone -n $frames -r $rate -c $channel_p -f $format -F $frequency -k $sigmak"
    alsabat "-P${pcm_p}" --standalone -n "${frames}" -c "${channel_p}" -r "${rate}" -f "${format}" -F "${frequency}" -k "${sigmak}" & playPID=$!

    # playback may have low latency, add one second delay to aviod recording zero at beginning.
    sleep 1

    # Select the first card
    first_card_name=$(aplay -l | awk '/^card ([0-9]+)/ {print $3; exit}')
    # dump amixer contents always.
    # Good case amixer settings is for reference, bad case for debugging.
    amixer -c "${first_card_name}" contents > "$LOG_ROOT"/amixer_settings.txt

    # We use different USB sound cards in CI, part of them only support 1 channel for capture,
    # so make the channel as an option and config it in alsabat-playback.csv
    dlogc "alsabat -C$pcm_c -c $channel_c -r $rate -f $format -F $frequency -k $sigmak"
    alsabat "-C${pcm_c}" -c "${channel_c}" -r "${rate}" -f "${format}" -F "${frequency}" -k "${sigmak}" || {
            # upload failed wav file
            __upload_wav_file
            exit 1
    }

    wait $playPID
}

main()
{
    start_test

    if [ "$SOF_TEST_PIPEWIRE" == true ] && [[ "$TPLG" == *rt712* ]]; then
        skip_test "Skipping: test not supported for RT712 configuration"
    fi

    if [ "$pcm_p" = "" ]||[ "$pcm_c" = "" ];
    then
        dloge "No playback or capture PCM is specified. Skip the alsabat test"
        exit 2
    fi

    check_locale_for_alsabat

    logger_disabled || func_lib_start_log_collect

    set_alsa

    if [ "$SOF_TEST_PIPEWIRE" == true ]; then
        run_test_on_pipewire
    else
        run_test_on_alsa_direct_mode
    fi
}

{
    main "$@"; exit "$?"
}
