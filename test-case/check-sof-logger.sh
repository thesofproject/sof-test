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

tmp_file=/tmp/$RANDOM.sof-logger.log

func_lib_check_sudo

dlogi "Try to dump the dma trace log via sof-logger ..."
dlogc "sudo $loggerBin -t -l $ldcFile -o $tmp_file 2>&1 &"
sudo $loggerBin -t -l $ldcFile -o $tmp_file 2>&1 &
sleep 2
dlogc "sudo pkill -9 $(basename $loggerBin)"
sudo pkill -9 $(basename $loggerBin) 2> /dev/null

# get size of trace log$
size=`du -k $tmp_file | awk '{print $1}'`
if [[ $size -lt 1 ]]; then
    dloge "No available log export."
    exit 1
fi
dlogi "Log data BEG>>"
cat $tmp_file
dlogi "<<END log data"
exit 0
