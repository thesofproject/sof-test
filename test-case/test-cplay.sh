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

OPT_NAME['p']='pcm_p'     	    OPT_DESC['p']='pcm for playback. Example: hw:0,0'
OPT_HAS_ARG['p']=1          	OPT_VAL['p']=''

OPT_NAME['C']='channel_c'       OPT_DESC['C']='channel number for capture.'
OPT_HAS_ARG['C']=1              OPT_VAL['C']='1'

OPT_NAME['N']='channel_p'       OPT_DESC['N']='channel number for playback.'
OPT_HAS_ARG['N']=1              OPT_VAL['N']='2'

OPT_NAME['r']='rate'            OPT_DESC['r']='sample rate'
OPT_HAS_ARG['r']=1              OPT_VAL['r']=48000

OPT_NAME['c']='pcm_c'      	    OPT_DESC['c']='pcm for capture. Example: hw:1,0'
OPT_HAS_ARG['c']=1              OPT_VAL['c']=''

OPT_NAME['f']='format'          OPT_DESC['f']='target format'
OPT_HAS_ARG['f']=1              OPT_VAL['f']="S16_LE"

OPT_NAME['F']='frequency'       OPT_DESC['F']='target frequency'
OPT_HAS_ARG['F']=1              OPT_VAL['F']=821

OPT_NAME['k']='sigmak'		    OPT_DESC['k']='sigma k value'
OPT_HAS_ARG['k']=1              OPT_VAL['k']=2.1

OPT_NAME['n']='frames'          OPT_DESC['n']='test frames'
OPT_HAS_ARG['n']=1              OPT_VAL['n']=240000

OPT_NAME['s']='sof-logger'      OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0              OPT_VAL['s']=1

OPT_NAME['d']='duration'        OPT_DESC['d']='duration time for socwatch to collect the data'
OPT_HAS_ARG['d']=1              OPT_VAL['d']=10

: "${SOCWATCH_PATH:=$HOME/socwatch}"
SOCWATCH_VERSION=$(sudo "$SOCWATCH_PATH"/socwatch --version | grep Version)

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
duration=${OPT_VAL['d']}

analyze_socwatch_results()
{
    pc_states_file="$LOG_ROOT/pc_states.csv"
    touch "$pc_states_file"
    results=$(cat "$socwatch_output".csv | grep "Platform Monitoring Technology CPU Package C-States Residency Summary: Residency" -A 10)
    echo "$results" | tee "$pc_states_file"

    expected_results='{"PC0":12.00, "PC2":88, "PC6.1":0, "PC6.2":11, "PC10.1":2, "PC10.2":72, "PC10.3":0}'

    # Analyze if the % of the time spent in given PC state was as expected
    if python3 "$SCRIPT_HOME"/tools/analyze-pc-states.py "$pc_states_file" "$expected_results"; then
        dlogi "All Package Residency (%) values were as expected"
    else
        die "Some Package Residency (%) values different from expected!"
    fi
}

check_for_PC10_state()
{
    pc10_count=$(awk '/Package C-State Summary: Entry Counts/{f=1; next} f && /PC10/{print $3; exit}' "$socwatch_output".csv)
    if [ -z "$pc10_count" ]; then
        die "PC10 State not achieved"
    fi
    dlogi "Entered into PC10 State $pc10_count times"

    pc10_per=$(awk '/Package C-State Summary: Residency/{f=1; next} f && /PC10/{print $3; exit}' "$socwatch_output".csv)
    pc10_time=$(awk '/Package C-State Summary: Residency/{f=1; next} f && /PC10/{print $5; exit}' "$socwatch_output".csv)
    dlogi "Spent $pc10_time ms ($pc10_per %) in PC10 State"

    json_str=$( jq -n \
                --arg id "$i" \
                --arg cnt "$pc10_count" \
                --arg time "$pc10_time" \
                --arg per "$pc10_per" \
                '{$id: {pc10_entires_count: $cnt, time_ms: $time, time_percentage: $per}}' )

    results=$(jq --slurp 'add' <(echo "$results") <(echo "$json_str"))
}

check_the_pcms()
{
    aplay   "-Dplug${pcm_p}" -d 1 /dev/zero -q || die "Failed to play on PCM: ${pcm_p}"
    arecord "-Dplug${pcm_c}" -d 1 /dev/null -q || die "Failed to capture on PCM: ${pcm_c}"
}

# Checks for soundfile needed for test, generates missing ones
prepare_test_soundfile()
{
    mkdir -p "$HOME/Music"
    if [ ! -f "$audio_filename" ]; then
        generate_mp3_file "$audio_filename"
    fi
}

run_test()
{
    check_the_pcms
    # audio_filename="$HOME/Music/test.mp3"
    # prepare_test_soundfile

    socwatch_output="$LOG_ROOT/socwatch-results/socwatch_report"

    # play_command="cplay -D${pcm_p} -d ${duration} ${audio_filename}"
    play_command=(aplay -Dplug${pcm_p} -d ${duration} /dev/zero)
    run_with_socwatch "$socwatch_output" "${play_command[@]}"
    
    analyze_socwatch_results
}

main()
{
    export RUN_SOCWATCH=true
    start_test
    if [ "$pcm_p" = "" ]||[ "$pcm_c" = "" ];
    then
        dloge "No playback or capture PCM specified."
        exit 2
    fi
    logger_disabled || func_lib_start_log_collect

    run_test
}

{
    main "$@"; exit "$?"
}
