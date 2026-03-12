#!/bin/bash

##
## Case Name: test-compressed-audio
##
## Preconditions:
##    TODO
##
## Description:
##    TODO
##
## Case step:
##    TODO
##
## Expect result:
##    TODO
##

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['p']='pcm_p'     	    OPT_DESC['p']='compression device for playback. Example: 50'
OPT_HAS_ARG['p']=1          	OPT_VAL['p']=''

OPT_NAME['N']='channels_p'       OPT_DESC['N']='channel number for playback.'
OPT_HAS_ARG['N']=1              OPT_VAL['N']='2'

OPT_NAME['s']='sof-logger'      OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0              OPT_VAL['s']=1

OPT_NAME['d']='duration'        OPT_DESC['d']='duration time for playing the test sound'
OPT_HAS_ARG['d']=1              OPT_VAL['d']=10

: "${SOCWATCH_PATH:=$HOME/socwatch}"
SOCWATCH_VERSION=$(sudo "$SOCWATCH_PATH"/socwatch --version | grep Version)

func_opt_parse_option "$@"
setup_kernel_check_point

pcm_p=${OPT_VAL['p']}
channels_p=${OPT_VAL['N']}
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

# Checks for soundfile needed for test, generates missing ones
prepare_test_soundfile()
{
    if [ ! -f "$audio_filename" ]; then
        dlogi "Generating audio file for the test..."
        generate_mp3_file "$audio_filename" "$duration" "$channels_p"
    fi
}

run_test()
{
    audio_filename="$HOME/Music/$channels_p-ch-$duration-s.mp3"
    prepare_test_soundfile

    socwatch_output="$LOG_ROOT/socwatch-results/socwatch_report"

    # cplay -c 0 -d "$pcm_p" -I MP3 "$audio_filename" -v

    play_command=("cplay" "-c" "0" "-d" "$pcm_p" "-I" "MP3" "${audio_filename}" "-v")
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
