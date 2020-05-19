# ASRC topology test
ASRC topology test is manual test for now

# Preconditions
1. Rename ASRC tplg to normal tplg to use
2. PulseAudio should be enabled

# Test Description
* Check playback and capture piplines can works normally with ASRC tplg

## Test Case:
1. Rename ASRC tplg to normal tplg to use, such as `sudo mv /lib/firmware/intel/sof/tplg/sof-hda-asrc-2ch.tplg /lib/firmware/intel/sof/tplg/sof-hda-generic-2ch.tplg`
2. Reboot system -> SOF is loaded successfully
3. Export TPLG, such as `export TPLG=/lib/firmware/intel/sof-tplg/sof-hda-generic-2ch.tplg`
4. Verify PCM list via `./../verify-pcm-list.sh`
5. Verify playback piplines via `./../check-playback.sh -d 3 -l 1 -r 1`
6. Verify capture piplines via `./../check-capture.sh -d 3 -l 1 -r 1`

## Expected results
* SOF can be loaded successfully and piplines works ok with ASRC tplg

