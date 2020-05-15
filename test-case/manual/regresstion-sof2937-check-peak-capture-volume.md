# sof#2937 Regression test
The capture peak volume tests are regression tests based on a DMIC peak volume issue documented in [sof#2937](https://github.com/thesofproject/sof/issues/2937)

# Preconditions
SOF is loaded

# Test Descriptioni
* Check that capture piplines volume is 00% once change volume to minimum value
* Check that capture piplines peak volume is 99%% once change volume to max value

## Playback Test Case:
1. `arecord -l` to check supported PCM
2. `arecord -Dhw:0,0 -r 48000 -f s16_le -c2 1.wav -vv -i` to trigger arecord, supported params can be dumped via `arecord -Dhw:0,0 --dump-hw-params`
3. Open another terminal, `alsamixer`, press tab button to switch to Capture page, find PGA volume for current PCM, normally is 'PGA2.0 0'
4. Downgrade volume to 0, check capture volume is downgraded to 00% in arecord terminal
5. Increase volume to max 100, check capture volume is 99% from arecord terminal
6. Press ctrl and c button to stop arecord
7. Repeat step 2 to step 6 for other capture piplins, such DMIC capture for Dhw:0,6

## Expected results
* Capture peak volume is 99% once change to volume to max

