#!/bin/bash

# Current: load it from dmesg
# Future: possibly be loaded from elsewhere
# Notice: Only verified on Ubuntu 18.04
tplg_file=$(journalctl -k |grep topology|awk -F ':' '/tplg/ {print $NF;}'|tail -n 1)
[[ ! "$tplg_file" ]] && \
    tplg_file=$(grep topology /var/log/kern.log|awk -F ':' '/tplg/ {print $NF;}'|tail -n 1)
[[ ! "$tplg_file" ]] && \
    tplg_file=$(grep topology /var/log/syslog|awk -F ':' '/tplg/ {print $NF;}'|tail -n 1)
[[ "$tplg_file" ]] && basename $tplg_file || echo ""
