#!/bin/bash

disk_health=85
declare -a disk_lst
for disk in $(findmnt -l |grep '[[:blank:]]/dev'|grep -v 'loop'|awk '{print $2;}')
do
    size=$(df -h $disk|awk '/[0-9]%/ {print $(NF -1)}'|sed 's/%//g')
    if [[ $size -ge $disk_health ]]; then
        disk_lst=("${disk_lst[@]}" $disk)
    fi
done

[[ ${#disk_lst} -eq 0 ]] && \
    echo "disk usage check: health" && \
    exit 0

echo -e "disk usage check: \e[31m\e[5mwarnning\e[0m\e[25m"
df -h --total ${disk_lst[@]}

exit 1
