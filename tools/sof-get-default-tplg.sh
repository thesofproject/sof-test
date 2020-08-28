#!/bin/bash

tplg_file=$(journalctl -k |grep -i topology |awk -F ':' '/tplg/ {print $NF;}'|tail -n 1)
[[ "$tplg_file" ]] && basename $tplg_file || echo ""
