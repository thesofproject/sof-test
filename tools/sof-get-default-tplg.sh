#!/bin/bash
#
# read kernel log to get topology file loaded by SOF driver
# Example from an apl up2 pcm512x device:
#
# sof-audio-pci 0000:00:0e.0: loading topology:intel/sof-tplg/sof-apl-pcm512x.tplg
#
# /lib/firmware/intel/sof-tplg/sof-apl-pcm512x.tplg will be returned
#
# CAVEAT: the SOF drivers CANNOT predict which particular
# /lib/firmware/[updates]/[5.16.12]/ base directory will be used and the
# kernel is hopelessly quiet about what firmware files it loads so this
# script always assumes '/lib/firmware/' See
# https://github.com/thesofproject/sof-test/issues/667

set -e

main()
{
    local tplg_file

    # Find the most recently loaded
    tplg_file=$(sudo journalctl -q -k -g 'loading topology' |
                awk -F: '{ topo=$NF; } END { print topo }'
             )

    [ -n "$tplg_file" ] || {
        >&2 printf 'ERROR: no topology loading found in kernel logs\n'
        # At least one test (check-reboot) relies on an empty stdout
        exit 1
    }

    tplg_file=/lib/firmware/"$tplg_file"

    # Make sure we were not tricked by /lib/firmware/updates/ or any
    # other issue.
    [ -e  "$tplg_file" ] || {
        >&2 printf '%s found in the kernel logs but not on the filesystem??\n' \
            "$tplg_file"
        exit 1
    }

    printf '%s\n' "$tplg_file"
}

main "$@"
