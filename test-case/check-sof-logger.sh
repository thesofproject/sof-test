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

source $(dirname ${BASH_SOURCE[0]})/../case-lib/lib.sh

func_opt_parse_option "$@"

#TODO: need to add arguments for user to give location for logger and ldc file

# hijack CASE_KERNEL_START_TIME which refer dump kernel log in exit function
unset CASE_KERNEL_START_TIME

# check sof-logger location
if [ -z $(which sof-logger) ]; then
    dloge "sof-logger Not Installed!"
    exit 1
fi

if [ $(which -a sof-logger|wc -l) -ne 1 ]; then
    dlogw "There are multiple sof-loggers in system"
    dlogw "using " `which sof-logger`
fi
loggerBin=$(which sof-logger)
dlogi "Found file: $(md5sum $loggerBin|awk '{print $2, $1;}')"

# check ldc file in /etc/sof/
platform=$(sof-dump-status.py -p)
ldcFile=/etc/sof/sof-$platform.ldc
dlogi "Checking ldc File: $ldcFile ..."
if [[ ! -f $ldcFile ]]; then
    dloge "File ($ldcFile) Not Found!"
    exit 1
fi
dlogi "Found file: $(md5sum $ldcFile|awk '{print $2, $1;}')"

data_file=$LOG_ROOT/logger.data.log
error_file=$LOG_ROOT/logger.error.log

func_lib_check_sudo

dlogi "Try to dump the dma trace log via sof-logger ..."
# sof-logger errors will output to $error_file
dlogc "sudo $loggerBin -t -l $ldcFile -o $data_file 2> $error_file &"
sudo bash -c "'$loggerBin -t -l $ldcFile -o $data_file 2> $error_file &'"
sleep 2
dlogc "sudo pkill -9 $(basename $loggerBin)"
sudo pkill -9 $(basename $loggerBin) 2> /dev/null

func_logger_exit()
{
    local code=$1 type=${2:-data}
    dlogi "Log $type BEG>>"
    cat $LOG_ROOT/logger.$type.log
    dlogi "<<END $type data"
    exit $code
}

# check if we get any sof-logger errors
logger_err=`grep -i "error" $error_file`
if [[ $logger_err ]]; then
    dloge "No available log to export due to sof-logger errors."
    func_logger_exit 1 'error'
fi

# '\.c\:[1-9]' to filter like '.c:6' this type keyword like:
# [3017136.770833]  (11.302083) c0 SA  src/lib/agent.c:65  ERROR validate(), ll drift detected, delta = 25549
fw_log_err=`grep -i "error" $data_file | grep -v '\.c\:[1-9]'`
# '[[:blank:]]TIMESTAMP.*CONTENT$' to filter the log header:
# TIMESTAMP  DELTA C# COMPONENT  LOCATION  CONTENT
if [[ ! $(sed -n '/[[:blank:]]TIMESTAMP.*CONTENT$/p' $data_file) ]]; then
    dloge "No available log to export."
    func_logger_exit 1
# we catch error from fw log
elif [[ $fw_log_err ]]; then
    dloge "Errors in firmware log:"
    func_logger_exit 1
fi

if [ "$(grep -i 'error' $data_file)" ]; then
    dlogw "Catch keyword 'ERROR' in firmware log"
fi

# no error with sof-logger and no error in fw log
func_logger_exit 0
