#!/bin/bash

##
## Case Name: check-sof-logger
## Preconditions:
##    sof-logger, cavstool.py and mtrace-reader.py installed in system path
##    dictionary (ldc) file is in /etc/sof/ or /lib/firmware
##
## Description:
##    Checks basic functionality of the logging tools. Does not test
##    the firmware, i.e., does NOT fail when errors are found in the
##    logs.
##
## Case step:
##    1. check existance of logging tools in system
##    2. check presence of dictionary files in system
##    3. run logging tools
## Expect result:
##    Fimrware log output is detected and the tools did not report error
##

set -e

TOPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=case-lib/lib.sh
source "${TOPDIR}"/case-lib/lib.sh

func_opt_parse_option "$@"

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

# etrace shared memory mailbox, newer feature.
etrace_file=$LOG_ROOT/logger.etrace.txt
etrace_stderr_file=$LOG_ROOT/logger.etrace_stderr.txt

func_lib_check_sudo

ping_pcm_devices()
{
    # Open all ALSA PCM nodes and read one byte out of them.
    # The operation will fail, but this is enough to cause
    # the device to be powered up if it was in runtime-suspended (D3)
    # state.
    for pcm in /dev/snd/pcm* ; do
        dd if="$pcm" of=/dev/null bs=1 count=1 >/dev/null 2>/dev/null || true
    done
}

run_loggers()
{
    # These filenames are kept for backward-compatibility
    # DMA trace
    local data_file=$LOG_ROOT/logger.data.txt
    # stderr
    local error_file=$LOG_ROOT/logger.error.txt

    local etrace_exit

    # This test is not really supposed to run while the DSP is busy at
    # the same time, so $data_file will hopefully not be long.
    local collect_secs=2


    # Avoid racing with runtime-pm by opening the PCM nodes just before logger
    # is started. This is still not bullet-proof, but at least we are
    # pinging the DSP as close as possible to start of log gathering.
    ping_pcm_devices

    if is_firmware_file_zephyr; then
        # Collect logs from Zephyr logging backends

        if is_ipc4 ; then
            # Get logs via SOF kernel IPC4 SRAM logging interfaces (mtrace)

            if [ -z "$MTRACE" ]; then
                MTRACE=$(command -v mtrace-reader.py) || {
                    die "No mtrace-reader.py found in PATH"
                }
            fi
            local mtracetool="$MTRACE"
            dlogi "Trying to get Zephyr logs from mtrace with background $mtracetool ..."
            dlogc \
                "sudo  $mtracetool >  $etrace_file  2>  $etrace_stderr_file"
            # shellcheck disable=SC2024
            sudo timeout -k 3 "$collect_secs" \
                 "$mtracetool" > "$etrace_file" 2> "$etrace_stderr_file" & mtracetoolPID=$!
        else
            # SOF kernel IPC3 SRAM logging interface (etrace)

            local cavstool
            cavstool=$(type -p cavstool.py)

            dlogi "Trying to get Zephyr logs from etrace with background $cavstool ..."
            dlogc \
                "sudo  $cavstool  --log-only >  $etrace_file  2>&1"
            # Firmware messages are on stdout and local messages on
            # stderr. Merge them and then grep ERROR below.
            # shellcheck disable=SC2024
            sudo timeout -k 3 "$collect_secs" \
                 "$cavstool" --log-only > "$etrace_file" 2>&1 & cavstoolPID=$!
        fi
    fi

    if ! is_ipc4 ; then
        # Sof-logger DMA logging (IPC3 only)

        dlogi "Trying to get the DMA .ldc trace log with background sof-logger ..."
        dlogc \
            "sudo $loggerBin  -t -f 3 -l  $ldcFile   >  $data_file  2>  $error_file  &"
        # shellcheck disable=SC2024
        sudo timeout -k 3 "$collect_secs"  \
             "$loggerBin" -t -f 3 -l "$ldcFile" \
             > "$data_file" 2> "$error_file" & dmaPID=$!
    fi

    sleep "$collect_secs"

    if ! is_ipc4 ; then
        # Sof-logger DMA logging (IPC3 only)

        loggerStatus=0; wait "$dmaPID" || loggerStatus=$?
        # 124 is the normal timeout exit status
        test "$loggerStatus" -eq 124 || {
            cat "$error_file"
            die "timeout sof-logger returned unexpected: $loggerStatus"
        }
    fi

    if is_firmware_file_zephyr; then
        # Zephyr logging backends

        if is_ipc4 ; then
            # SOF kernel IPC4 SRAM logging interface (mtrace)

            loggerStatus=0; wait "$mtracetoolPID" || loggerStatus=$?
            test "$loggerStatus" -eq 124 || {
                cat "$etrace_file"
                cat "$etrace_stderr_file"
                die "timeout $mtracetool returned unexpected: $loggerStatus"
            }
        else
            # SOF kernel IPC3 SRAM logging interface (etrace)

            loggerStatus=0; wait "$cavstoolPID" || loggerStatus=$?
            test "$loggerStatus" -eq 124 || {
                cat "$error_file"
                die "timeout $cavstool returned unexpected: $loggerStatus"
            }
            ( set -x
              grep -i ERROR "$etrace_file" > "$etrace_stderr_file"
            ) || true
        fi

        # All Zephyr backends checked at this point, we can return
        return 0
    fi

    if ! is_ipc4 ; then
        # Sof-logger error log over SRAM (XTOS and IPC3 only, etrace)

        dlogi "Trying to get the .ldc log from the etrace mailbox ..."
        dlogc \
            "sudo $loggerBin    -f 3 -l  $ldcFile  2>  $etrace_stderr_file   >  $etrace_file"
        # shellcheck disable=SC2024
        sudo "$loggerBin"   -f 3 -l "$ldcFile" 2> "$etrace_stderr_file"  > "$etrace_file" || {
            etrace_exit=$?
            cat "$etrace_stderr_file" >&2
        }

        printf '\n'

        return $etrace_exit
    fi

    # XTOS IPC4 case
    return 0
}


dma_nudge()
{
    sudo timeout -k 5 2  "$loggerBin" -l "${ldcFile}" -F info=pga -t
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
    for ftype in "${stdout_files[@]}" "${stderr_files[@]}"; do
        printf '\n'
        bname="logger.$ftype.txt"
        dlogi "Log file $bname BEG::"
        cat "$LOG_ROOT/$bname" || true # we already checked these
        dlogi "::END log file $bname"
        printf '\n'
    done
    test -z "$errmsg" || dloge "$errmsg"

    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT" || exit_code=1

    exit "$exit_code"
}

reload_drivers()
{
    "${TOPDIR}"/tools/kmod/sof_remove.sh

    setup_kernel_check_point

    "${TOPDIR}"/tools/kmod/sof_insert.sh

    # The DSP may unfortunately need multiple retries to boot, see
    # https://github.com/thesofproject/sof/issues/3395
    dlogi "Polling ${CARD_NODE}, waiting for DSP boot..."
    if poll_wait_for 1 "$MAX_WAIT_FW_LOADING" sof_firmware_boot_complete --since=@"$KERNEL_CHECKPOINT"; then
        dlogi "DSP booted successfully."
    else
        die "DSP did not boot (node ${CARD_NODE})"
    fi
}

main()
{
    # Keeping these confusing DMA names because they're used in
    # several other places.
    if is_ipc4 ; then
        stdout_files=(etrace)
        stderr_files=(etrace_stderr)
    else
        stdout_files=(data  etrace)
        stderr_files=(error etrace_stderr)
    fi

    reload_drivers
    # cavstool is now racing against D3
    run_loggers

    local f

    for f in "${stderr_files[@]}"; do
        local stderr_file="$LOG_ROOT/logger.$f.txt"
        test -e "$stderr_file" || die "$stderr_file" not found
        if test -s "$stderr_file"; then
            print_logs_exit 1 "stderr $stderr_file is not empty"
        fi
        printf 'GOOD: %s was empty, no (std)err(or) output from that logger\n' \
               logger."$f".txt > "$stderr_file"
    done

    # Simulates a stuck DMA to test the code below
    # sed -i -e '2,$ d' "$LOG_ROOT/logger.data.txt"

    # Search for the log header, should be something like this:
    # TIMESTAMP  DELTA C# COMPONENT  LOCATION  CONTENT
    # then for the 'FW ABI' banner
    for f in "${stdout_files[@]}"; do
        local tracef="$LOG_ROOT/logger.$f.txt"
        local syst_prefix="SYS-T RAW DATA:"
        test -e "$tracef" || die "$tracef" not found

        local tool_banner boot_banner
        if is_ipc4 && is_firmware_file_zephyr && [ "$f" = 'etrace' ]; then
            # mtrace
            if head -n 5 "$tracef" | grep -q "$syst_prefix" ; then
                # MIPI Sys-T Catalog format, just search for Sys-T prefix
                # that is available without decoding tools and collateral
                tool_banner=$syst_prefix
                boot_banner=$syst_prefix
            else
                # ascii mtrace, no specfic tool banner, just check for some logs
                tool_banner=' .*<.*>'
                boot_banner='FW ABI.*tag.*zephyr'
            fi
        elif is_firmware_file_zephyr && [ "$f" = 'etrace' ]; then
            # cavstool
            tool_banner=':cavs-fw:'
            boot_banner='FW ABI.*tag.*zephyr'
        else
            # sof-logger
            # Other columns besides COMPONENT and CONTENT are optional
            tool_banner='COMPONENT.*CONTENT'
            boot_banner='dma-trace.c.*FW ABI.*tag.*hash'
        fi

        head -n 5 "$tracef" | grep -q "$tool_banner"  ||
            print_logs_exit 1 "Log header not found in ${tracef}"

        # See initial message SOF PR #3281 / SOF commit 67a0a69
        grep -i -q "$boot_banner" "$tracef" || {

            # Workaround for DMA trace bug
            # https://github.com/thesofproject/sof/issues/4333
            if [ "$f" = data ]; then
                dloge "Empty or stuck DMA trace? Let's try to nudge it."
                dloge '  vv  Workaround for SOF issue 4333  vv'
                local second_chance="$LOG_ROOT/logger.dma_trace_bug_4333.txt"
                dma_nudge | tee "$second_chance"
                printf '\n'
                dloge ' ^^ End of workaround nudge for 4333 ^^ '
                printf '\n'

                if head "$second_chance" |
                        grep -q 'dma-trace.c.*FW ABI.*tag.*hash'; then
                    continue # and don't report failure 4333
                fi
            fi

            print_logs_exit 1 "Initial FW ABI banner not found in ${tracef}"
        }
    done

    local OK=true

    for f in "${stdout_files[@]}"; do
        local tracef="$LOG_ROOT/logger.$f.txt"
        check_error_in_fw_logfile "$tracef" || {
            OK=false; printf '\n'
        }
    done

    # Show all outputs even when everything went OK
    if $OK; then
        print_logs_exit 0
    else
        print_logs_exit 1 "^^ ERROR(s) found in firmware logs ^^"
    fi
}

main "$@"
