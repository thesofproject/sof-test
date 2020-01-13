# Suspend-Resume with playback and capture test
Suspend-Resume with audio playback and capture is a manual test for now.

# Preconditions
1. N/A

# Test Description
* Check suspend/resume state during audio playback and capture
* Run aplay on playback pipeline
* Run arecord on capture pipeline
* Repeat suspend/resume test 100x for both aplay & arecord

## Playback Test Case:
1. Have a test audio .wav file matching given parameters.
2. Run in terminal 1:
```
aplay -Dhw:0,0 -fs16_le -c2 -r 48000 -vv -i resource/raw/test-<specified>.raw
```
3. Run in terminal 2:
```
su root
echo mem > /sys/power/state
```
4. Device and audio playback should suspend.
5. Press any key to wake up device.
6. Playback should resume when device resumes.
7. Repeat as necessary.
8. Check dmesg for any unexpected errors.

## Capture Test Case:
1. Run in terminal 1:
```
arecord -Dhw:0,0 -fs16_le -c2 -r 48000 -vv -i /dev/null
```
2. Run in terminal 2:
```
su root
echo mem > /sys/power/state
```
3. Device and audio capture should suspend.
4. Press any key to wake up device.
5. Audio capture should resume when device resumes.
6. Repeat as necessary.
7. Check dmesg for any unexpected errors.

## Expect result
* During playback test, audio quality should stay the same after suspend /
resume cycle.
* aplay /  arecord processes should continue to be active after suspend / resume
cycle.
* No unexpected errors should be present in dmesg during or after test
completion.
