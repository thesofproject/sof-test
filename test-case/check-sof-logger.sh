#!/bin/bash

##
## Case Name: check-sof-logger
## Preconditions:
##    sof-logger install in system path
##    ldc file is in /etc/sof/
## Description:
##    Check debug tools sof-logger can success work
## Case step:
##    1. check sof-logger in system
##    2. check ldc file in system
##    3. run sof-logger
## Expect result:
##    sof-logger already catch some thing
##

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

func_opt_parse_option "$@"

#TODO: need to add arguments for user to give location for logger and ldc file

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

data_file=$LOG_ROOT/logger.data.txt
error_file=$LOG_ROOT/logger.error.txt

func_lib_check_sudo

dlogi "Try to dump the dma trace log via sof-logger ..."
# sof-logger errors will output to $error_file
dlogc "sudo $loggerBin -t -l $ldcFile -o $data_file 2> $error_file &"
sudo bash -c "'$loggerBin -t -l $ldcFile -o $data_file 2> $error_file &'"
sleep 2
dlogc "sudo pkill -9 $(basename "$loggerBin")"
sudo pkill -9 "$(basename "$loggerBin")" 2> /dev/null

func_logger_exit()
{
    local code=$1

    for ftype in data error; do
        printf '\n'
        dlogi "Log $ftype BEG::"
        cat "$LOG_ROOT/logger.$ftype.log"
        dlogi "::END $ftype"
    done
    exit "$code"
}

# check if we get any sof-logger errors
logger_err=$(grep -i 'error' "$error_file")
if [[ $logger_err ]]; then
    dloge "No available log to export due to sof-logger errors."
    func_logger_exit 1
fi

# '\.c\:[1-9]' to filter like '.c:6' this type keyword like:
# [3017136.770833]  (11.302083) c0 SA  src/lib/agent.c:65  ERROR validate(), ll drift detected, delta = 25549
fw_log_err=$(grep -i 'error' "$data_file" | grep -v '\.c\:[1-9]')

# '[[:blank:]]TIMESTAMP.*CONTENT$' to filter the log header:
# TIMESTAMP  DELTA C# COMPONENT  LOCATION  CONTENT
if [[ ! $(sed -n '/TIMESTAMP.*CONTENT/p' "${data_file}") ]]; then
    dloge "Log header not found in ${data_file}"
    func_logger_exit 1
# we catch error from fw log
elif [[ $fw_log_err ]]; then
    dloge "Error(s) found in firmware log ${data_file}"
    func_logger_exit 1
fi

if grep -i -q 'error' "$data_file" ; then
    dlogw "Catch keyword 'ERROR' in firmware log"
fi

# no error with sof-logger and no error in fw log
func_logger_exit 0
