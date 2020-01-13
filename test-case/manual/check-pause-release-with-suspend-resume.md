# Pause-Release with Suspend-Resume
Pause-Release + Suspend-Resume is a manual test for now.

# Preconditions
1. Device has ability to fully suspend.
   - BYTs cannot enter necessary suspend state.

# Test Description
* Check for errors during test cycle of:
  playback -> pause -> suspend -> resume -> release cycles

## Test Case:
1. Run in terminal 1:
```
aplay -Dhw:0,0 -fs16_le -c2 -r 48000 -vv -i /dev/zero
```
2. Press the spacebar to pause playback

3. Run in terminal 2:
```
sudo rtcwake -m mem -s 10
```
4. Device should suspend.
5. Once device has resumed, press spacebar in terminal 1 to release audio
playback from paused state.
6. Playback should resume normally.
7. Check dmesg for any unexpected errors.
8. Repeat as necessary.

## Expect result.
* aplay process should continue to be active after suspend / resume cycle.
* No unexpected errors should be present in dmesg during or after test
completion.
