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
source "$TOPDIR"/case-lib/lib.sh

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=1

OPT_NAME['d']='duration' OPT_DESC['d']='duration time for socwatch to collect the data'
OPT_HAS_ARG['d']=1         OPT_VAL['d']=20

OPT_NAME['w']='wait'     OPT_DESC['w']='idle time before starting socwatch to collect the data'
OPT_HAS_ARG['w']=1         OPT_VAL['w']=5

# TODO: socwatch test after unloading audio module might be useful
OPT_NAME['u']='unload-audio'  OPT_DESC['u']='unload audio modules for the test'
OPT_HAS_ARG['u']=0            OPT_VAL['u']=0

# TODO: every time should install socwatch? yes, must deploy everytime with built socwatch modules
# FIXME: change to right path, probably ~/socwatch
#SOCWATCH_PATH="$HOME/Downloads/socwatch_chrome_linux_INTERNAL_v2023.3.0_x86_64"
SOCWATCH_PATH="$HOME/socwatch"

# reference cmd: sudo ./socwatch -t 20 -s 5 -f cpu-cstate -f pkg-pwr -o fredtest5
#SOCWATCH_CMD="./socwatch"
SOCWATCH_FEATURE_PARAMS="-f cpu-cstate -f pkg-pwr"

func_opt_parse_option "$@"
func_lib_check_sudo
duration=${OPT_VAL['d']}
wait_time=${OPT_VAL['w']}
loop_count=${OPT_VAL['l']}

check_socwatch_module_loaded()
{
    sudo lsmod | grep -q socwatch || {
        die "socwatch kernel module not loaded"
    }
}

socwatch_test_once()
{
    local i="$1"
    dlogi "===== Loop($i/$loop_count) ====="
    
    # set up checkpoint for each iteration
    setup_kernel_check_point

    # load socwatch module
    sudo $SOCWATCH_PATH/insmod-socwatch
    check_socwatch_module_loaded || die "socwatch module not loaded"

    dlogc "Run the command: socwatch -t $duration -s $wait_time $SOCWATCH_FEATURE_PARAMS -o $SOCWATCH_PATH/sofsocwatch-$i"
    sudo "$SOCWATCH_PATH"/socwatch -t "$duration" -s "$wait_time" $SOCWATCH_FEATURE_PARAMS -o "$SOCWATCH_PATH/sofsocwatch-$i" || die "socwatch returned $?"

    # filter output and copy to log directory
    grep "Package C-State Summary: Residency" -B 8 -A 11 "$SOCWATCH_PATH/sofsocwatch-$i.csv" >> "$SOCWATCH_PATH/socwatch-$i.txt"
    grep "Package Power Summary: Average Rate" -B 6 -A 4 "$SOCWATCH_PATH/sofsocwatch-$i.csv" >> "$SOCWATCH_PATH/socwatch-$i.txt"
    cp "$SOCWATCH_PATH/socwatch-$i.txt" "$SOCWATCH_PATH/sofsocwatch-$i.csv" "$LOG_ROOT"/

    dlogi "Check for the kernel log status"
    # check kernel log for each iteration to catch issues
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" || die "Caught error in kernel log"

    # unload socwatch module
    sudo "$SOCWATCH_PATH"/rmmod-socwatch
}

main()
{
    local keep_modules=true already_unloaded=false

    if [ ! -d "$SOCWATCH_PATH" ]; then
        die "SOCWATCH is not installed properly"
    fi

    if [ "${OPT_VAL['u']}" = 1 ]; then
        keep_modules=false
    fi

    sudo lsmod | grep -q snd.sof || {
        already_unloaded=true
        $keep_modules ||
            dlogw 'modules already unloaded, ignoring option -u!'
    }

    $already_unloaded || $keep_modules || "$TOPDIR"/tools/kmod/sof_remove.sh ||
        die "Failed to unload audio drivers"

    # socwatch test from here
    for i in $(seq 1 "$loop_count")
    do
        socwatch_test_once "$i"
    done

    $already_unloaded || $keep_modules || "$TOPDIR"/tools/kmod/sof_insert.sh ||
        die "Failed to reload audio drivers"
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" ||
        die "Found kernel error after reloading audio drivers"

    # TODO: delete socwatch directory from the device after the test
    # rm -rf $SOCWATCH_PATH
}

main "$@"
