#!/bin/bash

log_file="/var/log/kern.log"
bootup_keyword='\[    0.000000\] Linux version '"$(uname -r)"
# tr '\0' ' ' to fix warning message: "command substitution: ignored null byte in input"
base_info=$(grep -na "$bootup_keyword" $log_file|tr '\0' ' ')
# rollback to kern.log.1, OS will write the log into the different file
# so here when current log file: kern.log miss the system boot information
# rollback catch from kern.log.1, normally just 1 file is enough to cache it
[[ ! "$base_info" ]] && log_file="/var/log/kern.log.1"
boot_line=$(grep -na "$bootup_keyword" $log_file |tr '\0' ' '|sed -n '$p'|awk -F ':' '{print $1;}')
[[ ! "$boot_line"  ]] && boot_line=0
#sed -n "$boot_line,\$p" $log_file |awk '{ for(i=1; i<=4; i++){ $i="" }; print $0 }'|sed 's/^    //g'
sed -n "$boot_line,\$p" $log_file |cut -f5- -d ' '
[[ "$base_info" ]] && exit
# this logic means not find bootup information in the kern.log file, but find at kern.log.1
# so some information write at kern.log, it also need to dump
#cat /var/log/kern.log |awk '{ for(i=1; i<=4; i++){ $i="" }; print $0 }'|sed 's/^    //g'
cat /var/log/kern.log |cut -f5- -d ' '
