# Pulseaudio test
Pulseaudio testing is manual testing for now.

# Preconditions
1. PulseAudio should be enabled
2. UCM for the platform/device should be installed

# Test Description
* Change current audio device through Setting->Sound app in Ubuntu (different linux distros may have different app)
* Run paplay on playback pipeline
* Run parecord on capture pipeline
* Default duration is 10s
* Default loop count is 3

## Playback Test Case:
1. Check pulseaudio devices in Settings -> Sound, Output
2. Find current Output Device, select Speaker or Built-in audio if available
3. paplay via Speaker/Build-in audio pipeline - check sound and its volume
4. Select headset as Output Device if available
5. paplay via headset pipeline - check sound and its volume
6. Select HDMI/DisplayPort as Output Device if available
7. paplay via HDMI/DP pipeline - check sound and its volume
8. While playback is going on, change the Audio Output to another one. Check sound and its volume again
9. Select headset as Output Device if available
10. paplay via headset pipeline - check sound and its volume
11. Unplug headset, check Output Device is switched to the other one
12. Plug headset, and check the sound and its volume
13. Find current Output Device, select Speaker or Built-in audio if available
14. paplay via Speaker/Build-in audio pipeline - check sound and its volume
15. Suspend & Resume
16. paplay via Speaker/Build-in audio pipeline - check sound and its volume
17. Select headset as Output Device if available
18. paplay via headset pipeline - check sound and its volume
19. Suspend & Resume
20. paplay via headset pipeline - check sound and its volume
21. Select HDMI/DisplayPort as Output Device if available
22. paplay via HDMI/DP pipeline - check sound and its volume
23. Suspend & Resume
24. paplay via HDMI/DP pipeline - check sound and its volume

## Capture Test Case:
1. Check pulseaudio devices in Settings -> Sound, Input
2. Find current Input Device, select Headset if available
3. parecord via headset pipeline - check sound and its volume
4. Select DMIC as Input Device
5. parecord via DMIC pipeline - check sound and its volume
6. While capture is going on, change the Audio Input to another one. Check sound and its volume again
7. Find current Input Device, select Headset if available
8. parecord via headset pipeline - check sound and its volume
9. Suspend & Resume
10. parecord via headset pipeline - check sound and its volume
11. Select DMIC as Input Device
12. parecord via DMIC pipeline - check sound and its volume
13. Suspend & Resume
14. parecord via DMIC pipeline - check sound and its volume


## Expected results
* All devices should sound good
* The Volume of the device should be changed accordingly
* The return value of paplay/precord is 0
* After suspend & resume, playback and capture should work as before
