#!/bin/bash

set -e

##
## Case Name: check-soc-power-status
## Preconditions:
##    Intel SoCwatch tool must be installed on the device
## Description:
##    Run the socwatch command to check SoC power status
## Test steps:
##    1. load socwatch kernel module
##    2. run socwatch command with desired parameters
##    3. check return value from socwatch
##    4. collect logs
##    5. check dmesg errors
##    6. unload socwatch kernel module
## Expect result:
##    consistent power status across tests
##    check kernel log and find no errors
##

TOPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=case-lib/lib.sh
source "${TOPDIR}"/case-lib/lib.sh

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1       OPT_VAL['l']=1

OPT_NAME['d']='duration' OPT_DESC['d']='duration time for socwatch to collect the data'
OPT_HAS_ARG['d']=1       OPT_VAL['d']=20

OPT_NAME['w']='wait'     OPT_DESC['w']='idle time before starting socwatch to collect the data'
OPT_HAS_ARG['w']=1       OPT_VAL['w']=5

# TODO: socwatch test after unloading audio module might be useful
OPT_NAME['u']='unload-audio'  OPT_DESC['u']='unload audio modules for the test'
OPT_HAS_ARG['u']=0            OPT_VAL['u']=0

: "${SOCWATCH_PATH:=$HOME/socwatch}"
SOCWATCH_VERSION=$(sudo "$SOCWATCH_PATH"/socwatch --version | grep Version)

func_opt_parse_option "$@"
func_lib_check_sudo
duration=${OPT_VAL['d']}
wait_time=${OPT_VAL['w']}
loop_count=${OPT_VAL['l']}

start_test

check_socwatch_module_loaded()
{
    lsmod | grep -q socwatch || die "socwatch is not loaded"
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

socwatch_test_once()
{
    local i="$1"
    dlogi "===== Loop($i/$loop_count) ====="
    dlogi "SoCWatch version: ${SOCWATCH_VERSION}"

    socwatch_output="$LOG_ROOT/socwatch-results/socwatch_output_$i"

    # set up checkpoint for each iteration
    setup_kernel_check_point

    ( set -x
      sudo "$SOCWATCH_PATH"/socwatch -m -f sys -f cpu -f cpu-hw -f pcie -f hw-cpu-cstate \
      -f pcd-slps0 -f tcss-state -f tcss -f pcie-lpm -n 200 -t "$duration" -s "$wait_time" \
      -r json -o "$socwatch_output" ) ||
    die "socwatch returned $?"

    # analyze SoCWatch results
    check_for_PC10_state

    # check kernel log for each iteration to catch issues
    dlogi "Check for the kernel log status"
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" || die "Caught error in kernel log"
}

unload_modules()
{
    keep_modules=true
    already_unloaded=false

    [ -d "$SOCWATCH_PATH" ] ||
        die "SOCWATCH not found in SOCWATCH_PATH=$SOCWATCH_PATH"

    if [ "${OPT_VAL['u']}" = 1 ]; then
        keep_modules=false
    fi

    lsmod | grep -q snd_sof || {
        already_unloaded=true
        $keep_modules ||
            dlogw 'modules already unloaded, ignoring option -u!'
    }

    if ! [ $already_unloaded ] || [ $keep_modules ]; then
        "$TOPDIR"/tools/kmod/sof_remove.sh ||
        die "Failed to unload audio drivers"
    fi
}

load_modules()
{
    if ! [ $already_unloaded ] || [ $keep_modules ]; then
        "$TOPDIR"/tools/kmod/sof_insert.sh ||
        die "Failed to reload audio drivers"
    fi

    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" ||
        die "Found kernel error after reloading audio drivers"
}

run_socwatch_tests()
{
    # Create a dir for all socwatch reports
    mkdir "$LOG_ROOT/socwatch-results"
    pc10_results_file="$LOG_ROOT/socwatch-results/pc10_results.json"
    touch "$pc10_results_file"

    for i in $(seq 1 "$loop_count")
    do
        socwatch_test_once "$i"
    done
    echo "$results" > "$pc10_results_file"
    dlogi "****** PC10 STATE RESULTS: ******"
    dlogi "$results"
    dlogi "*********************************"

    # zip all SoCWatch reports
    cd "$LOG_ROOT"
    tar -zcvf socwatch-results.tar.gz socwatch-results/
    rm -rf "$LOG_ROOT/socwatch-results/"
}

main()
{
    unload_modules
    load_socwatch
    run_socwatch_tests
    unload_socwatch
    load_modules
}

main "$@"
