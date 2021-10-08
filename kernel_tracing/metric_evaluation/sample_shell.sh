#!/bin/sh
SOF_LOGGING=none TPLG=/lib/firmware/intel/sof-tplg/sof-hda-generic-4ch.tplg ../../test-case/check-playback.sh -l1
sleep 5
