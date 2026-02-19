#!/bin/bash

##
## Case Name: test-compressed-audio
## Preconditions:
##    - socwatch installed
##    - cplay installed
## Description:
##    This test verifies if we enter PC10 state when playing MP3 with offload to DSP.
## Case steps:
##    1. Generate MP3 sound for testing.
##    2. Start Socwatch measurement and play MP3 file.
##    3. Analyze Socwatch results.
## Expected results:
##    - generated MP3 is played
##    - dut stays in the PC10 state for the expected amount of time
##

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['p']='pcm_p'     	     OPT_DESC['p']='compression device for playback. Example: 50'
OPT_HAS_ARG['p']=1          	 OPT_VAL['p']=''

OPT_NAME['N']='channels_p'       OPT_DESC['N']='channel number for playback.'
OPT_HAS_ARG['N']=1               OPT_VAL['N']='2'

OPT_NAME['s']='sof-logger'       OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0               OPT_VAL['s']=1

OPT_NAME['d']='duration'         OPT_DESC['d']='duration time for playing the test sound'
OPT_HAS_ARG['d']=1               OPT_VAL['d']=10

OPT_NAME['pc10_per']='pc10_per'  OPT_DESC['pc10_per']='pc10 state threshold - percentage of time that should be spent in pc10'
OPT_HAS_ARG['pc10_per']=1        OPT_VAL['pc10_per']=80

: "${SOCWATCH_PATH:=$HOME/socwatch}"

func_opt_parse_option "$@"
setup_kernel_check_point

pcm_p=${OPT_VAL['p']}
channels_p=${OPT_VAL['N']}
duration=${OPT_VAL['d']}
pc10_threshold=${OPT_VAL['pc10_per']}

analyze_socwatch_results()
{
    pc_states_file="$LOG_ROOT/pc_states.csv"
    touch "$pc_states_file"
    results=$(grep "Platform Monitoring Technology CPU Package C-States Residency Summary: Residency" -A 10 < "$socwatch_output".csv)
    echo "$results" | tee "$pc_states_file"

    expected_results="{\"PC10.2\":$pc10_threshold}"

    # Analyze if the % of the time spent in given PC state was as expected
    if python3 "$SCRIPT_HOME"/tools/analyze-pc-states.py "$pc_states_file" "$expected_results"; then
        dlogi "All Package Residency (%) values were as expected"
    else
        die "Some Package Residency (%) values different from expected!"
    fi
}

# Checks for soundfile needed for test, generates missing ones
prepare_test_soundfile()
{
    if [ ! -f "$audio_filename" ]; then
        dlogi "Generating audio file for the test..."
        generate_mp3_file "$audio_filename" "$duration" "$channels_p"
    fi
}

check_cplay_command()
{
    dlogi "${play_command[@]}"
    "${play_command[@]}" || die "cplay command returned error, socwatch analysis not performed"
}

run_test()
{
    audio_filename="$HOME/Music/$channels_p-ch-$duration-s.mp3"
    prepare_test_soundfile

    socwatch_output="$LOG_ROOT/socwatch-results/socwatch_report"

    play_command=("cplay" "-c" "0" "-d" "$pcm_p" "-I" "MP3" "${audio_filename}" "-v")
    check_cplay_command

    run_with_socwatch "$socwatch_output" "${play_command[@]}"
    
    analyze_socwatch_results
}

main()
{
    export RUN_SOCWATCH=true
    start_test
    logger_disabled || func_lib_start_log_collect
    run_test
}

{
    main "$@"; exit "$?"
}
