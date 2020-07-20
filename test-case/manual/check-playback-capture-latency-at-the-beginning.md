# Latency test
Check latency at the beginning is manual test for piplines which isn't setup loopback for alsabat test

# Preconditions
SOF is loaded successfully

# Test Description
* Check playback latency at the beginning
* Check capture latency at the beginning

## Test Case:
1. `aplay -l` and `arecord -l` to check supported PCM
2. Wait for about 3s till runtime PM is suspended, can check via `cat "/sys/bus/pci/devices/0000:00:1f.3/power/runtime_status"`, the pci device id can be find from `lspci` for Multimedia audio controller
3. `aplay -Dhw:0,0 -r 48000 -f s16_le -c2 test.wav -vv -i` to trigger aplay from runtime PM suspended status, supported params can be dumped via `aplay -Dhw:0,0 --dump-hw-params`
4. Check audiou output without obvious delay, latency at the begining is within 1s
5. Press ctrl and c button to stop aplay
6. Repeat step 2 to step 5 for other playback piplines, such headset/HDMI/DP
7. Repeate step 2 to step 5 for capture piplines with `arecord -Dhw:0,0 -r 48000 -f s16_le -c2 1.wav -vv -i`, then play this recorded 1.wav file to check latency at the begining is within 1s


## Expected results
* Playback and capture latency at the beginning is within 1s
