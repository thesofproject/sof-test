#!/bin/bash

# Current: load TPLG file order:
# dmesg
# journalctl
# /var/log/syslog (sof-kernel-dump.sh)
# Future: possibly be loaded from elsewhere
# Notice: Only verified on Ubuntu 18.04
tplg_file=$(dmesg |grep -i topology|awk -F ':' '/tplg/ {print $NF;}'|tail -n 1)
[[ ! "$tplg_file" ]] && \
    tplg_file=$(journalctl -k |grep -i topology |awk -F ':' '/tplg/ {print $NF;}'|tail -n 1)
[[ ! "$tplg_file" ]] && \
    tplg_file=$(sof-kernel-dump.sh |grep -i topology|awk -F ':' '/tplg/ {print $NF;}'|tail -n 1)
[[ "$tplg_file" ]] && basename $tplg_file || echo ""
