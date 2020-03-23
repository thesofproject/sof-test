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

func_opt_parse_option $*

#TODO: need to add arguments for user to give location for logger and ldc file

# hijack DMESG_LOG_START_LINE which refer dump kernel log in exit function
DMESG_LOG_START_LINE=$(sof-get-kernel-line.sh|tail -n 1 |awk '{print $1;}')

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

rdnum=$RANDOM
tmp_file=/tmp/$rdnum.logger.log
err_tmp_file=/tmp/$rdnum.err_logger.log

func_lib_check_sudo

dlogi "Try to dump the dma trace log via sof-logger ..."
# sof-logger errors will output to $err_tmp_file
dlogc "sudo $loggerBin -t -l $ldcFile -o $tmp_file 2> $err_tmp_file &"
sudo $loggerBin -t -l $ldcFile -o $tmp_file 2> $err_tmp_file &
sleep 2
dlogc "sudo pkill -9 $(basename $loggerBin)"
sudo pkill -9 $(basename $loggerBin) 2> /dev/null

# check if we get any sof-logger errors
logger_err=`grep -i "error" $err_tmp_file`
if [[ $logger_err ]]; then
    dloge "No available log to export due to sof-logger errors."
    dlogi "Logger error BEG>>"
    cat $err_tmp_file
    dlogi "<<END Logger error"
    exit 1
fi
# get size of trace log$
size=`du -k $tmp_file | awk '{print $1}'`
fw_log_err=`grep -i "error" $tmp_file`
# 100 here is log header size
# only log header and no fw log
if [[ $size -le 100 ]]; then
    dloge "No available log to export."
    exit 1
# we catch error from fw log
elif [[ $fw_log_err ]]; then
    dloge "Errors in firmware log:"
    dlogi "Log data BEG>>"
    cat $tmp_file
    dlogi "<<END log data"
    exit 1
fi
# no error with sof-logger and no error in fw log
dlogi "Log data BEG>>"
cat $tmp_file
dlogi "<<END log data"
exit 0
