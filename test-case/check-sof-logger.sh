#!/bin/bash

##
## Case Name: check-sof-logger
## Preconditions:
##    sof-logger installed in system path
##    ldc file is in /etc/sof/ or /lib/firmware
##
## Description:
##    Checks basic functionality of the sof-logger itself. Does not test
##    the firmware, i.e., does NOT fail when errors are found in the
##    logs.
##
## Case step:
##    1. check sof-logger in system
##    2. check ldc file in system
##    3. run sof-logger
## Expect result:
##    sof-logger produces some output and did not fail
##

set -e

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

func_opt_parse_option "$@"

setup_kernel_check_point

# check sof-logger location
type -a sof-logger ||
    die "sof-logger Not Installed!"


# Checksum a list of files, one filename per stdin line.
# Whitespace-safe and shellcheck-approved.
md5list()
{
    while read -r; do md5sum "$REPLY"; done
}

# Recent Ubuntu versions symlink the entire /bin -> /usr/bin so we
# cannot just count the number of filenames we found. Count the
# number of different _checksums_ we found in PATH.
if type -a -p sof-logger | md5list | awk '{ print $1 }' |
        sort -u | tail -n +2 | grep -q . ; then
    dloge "There are different sof-logger in PATH on the system $(hostname)!"
    type -a -p sof-logger | md5list
    die "Not testing a random sof-logger version"
fi
loggerBin=$(type -p sof-logger)
dlogi "Found file: $(md5sum "$loggerBin" | awk '{print $2, $1;}')"

dlogi "Looking for ldc File ..."
ldcFile=$(find_ldc_file) || die ".ldc file not found!"

dlogi "Found file: $(md5sum "$ldcFile"|awk '{print $2, $1;}')"

# These filenames are kept for backward-compatibility
# DMA trace
data_file=$LOG_ROOT/logger.data.txt
# stderr
error_file=$LOG_ROOT/logger.error.txt

# etrace shared memory mailbox, newer feature.
etrace_file=$LOG_ROOT/logger.etrace.txt
etrace_stderr_file=$LOG_ROOT/logger.etrace_stderr.txt

func_lib_check_sudo

run_loggers()
{
    local etrace_exit

    # This test is not really supposed to run while the DSP is busy at
    # the same time, so $data_file will hopefully not be long.
    local dma_collect_secs=2

    dlogi "Trying to get the DMA trace log with background sof-logger ..."
    dlogc \
    "sudo $loggerBin  -t -f 3 -l  $ldcFile  -o  $data_file  2>  $error_file  &"
    sudo timeout -k 3 --preserve-status "$dma_collect_secs"  \
         "$loggerBin" -t -f 3 -l "$ldcFile" \
         -o "$data_file" 2> "$error_file" & dmaPID=$!

    sleep "$dma_collect_secs"
    wait "$dmaPID"

    dlogi "Trying to get the etrace mailbox ..."
    dlogc \
    "sudo $loggerBin    -f 3 -l  $ldcFile  2>  $etrace_stderr_file  -o  $etrace_file"
    sudo "$loggerBin"   -f 3 -l "$ldcFile" 2> "$etrace_stderr_file" -o "$etrace_file" ||
        etrace_exit=$?

    printf '\n'

    return $etrace_exit
}

# Dumps all logs before exiting
print_logs_exit()
{
    local exit_code="$1" errmsg="$2"

    # Print $errmsg twice: - once _after_ the (possibly long) logs
    # because the end is where everyone logically looks atfirst when the
    # test fails, and; - also now _before_ the logs in case something
    # goes wrong and we don't make it until the end.
    test -z "$errmsg" || dloge "$errmsg"

    local bname
    for ftype in data etrace error etrace_stderr; do
        printf '\n\n'
        bname="logger.$ftype.txt"
        dlogi "Log file $bname BEG::"
        cat "$LOG_ROOT/$bname" || true # we already checked these
        dlogi "::END log file $bname"
    done
    test -z "$errmsg" || dloge "$errmsg"
    exit "$exit_code"
}

main()
{
    run_loggers ||
        print_logs_exit 1 "Reading etrace failed, run_loggers returned $?"

    local f

    for f in etrace_stderr error; do
        local stderr_file="$LOG_ROOT/logger.$f.txt"
        test -e "$stderr_file" || die "$stderr_file" not found
        if test -s "$stderr_file"; then
            print_logs_exit 1 "stderr $stderr_file is not empty"
        fi
        printf 'GOOD: %s was empty, no stderr output from that sof-logger instance\n' \
               logger."$f".txt > "$stderr_file"
    done

    # Search for the log header, should be something like this:
    # TIMESTAMP  DELTA C# COMPONENT  LOCATION  CONTENT
    for f in etrace data; do
        local tracef="$LOG_ROOT/logger.$f.txt"
        test -e "$tracef" || die "$tracef" not found
        # Other columns are optional
        head -n 1 "$tracef" | grep -q 'COMPONENT.*CONTENT'  ||
            print_logs_exit 1 "Log header not found in ${data_file}"

        # See initial message SOF PR #3281 / SOF commit 67a0a69
        grep -q 'dma-trace.c.*FW ABI.*tag.*hash' "$tracef" ||
            print_logs_exit 1 "Initial FW ABI banner not found in ${data_file}"
    done

    # This is a bit redundant with the previous test but does not hurt.
    tail -n +2 "${data_file}" | grep -q '[^[:blank:]]' ||
        print_logs_exit 1 "Nothing but the first line in DMA trace ${data_file}"

    # Show all outputs even when everything went OK
    print_logs_exit 0
}

main "$@"
