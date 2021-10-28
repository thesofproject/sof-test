#!/bin/bash
#
# read kernel log to get topology file loaded by SOF driver
# Example from an apl up2 pcm512x device:
#
# sof-audio-pci 0000:00:0e.0: loading topology:intel/sof-tplg/sof-apl-pcm512x.tplg
#
# sof-apl-pcm512x.tplg will be returned
#

tplg_file=$(sudo journalctl -k |grep -i topology |awk -F ':' '/tplg/ {print $NF;}'|tail -n 1)
[[ "$tplg_file" ]] && basename "$tplg_file" || echo ""
