# Pulseaudio Mute LED test
Mute LED testing is manual testing for now.

# Preconditions
1. PulseAudio should be enabled
2. UCM for the platform/device should be installed
3. Test unit support Speaker mute LED or MIC mute LED

# Test Description
* Change current audio device through Setting->Sound app in Ubuntu (different linux distros may have different app)
* Change audio output mute and unmute via sound setting or via Speaker Mute button
* Change audio input mute and unmute via sound setting or via MIC mute button

## Playback Mute LED Test Case:
1. Select Speaker as output Device.
2. Paplay via speaker
3. Mute and unmute output via sound output setting volume bar or Speaker output Mute button ->Output Mute LED is light on when muted and light off when unmuted.
4. Select headset as Output Device if available
5. paplay via headset pipeline 
6. Mute and unmute output via sound output setting volume bar or output Mute button ->Output Mute LED is light on when muted and light off when unmuted.
7. Select HDMI/DisplayPort as Output Device if available
8. paplay via HDMI/DP pipeline 
9. Mute and unmute output via sound output setting volume bar or Speaker output Mute button ->Output Mute LED is light on when muted and light off when unmuted.
10. Suspend & Resume
11. Output mute LED still light on for muted
12. Sudo reboot when speaker output is muted ->Speaker output keeps muted after boot up.

## Capture Mute LED Test Case:
1. Select DMIC as Input Device
2. parecord via DMIC pipeline 
3. Mute input via sound input setting mute/unmute switch button or via drag volume down to 0 till muted in sound setting or via MIC Mute button on keyboard ->MIC Mute LED is light on when muted 
4. Unmute input via sound input setting mute/unmute switch button or via drag volume up to max in sound setting or via MIC Mute button on keyboard ->MIC Mute LED is light off when unmuted
5. Select Headset Microphone as Input Device
6. Parecord via headset pipeline 
7. Mute and unmute input via sound input setting volume bar or MIC Mute button ->MIC Mute LED is light on when muted and light off when unmuted.
8. Select Headphone Microphone as Input Device if available
9. Parecord via headset pipeline 
10. Mute and unmute input via sound input setting volume bar or MIC Mute button ->MIC Mute LED is light on when muted and light off when unmuted.
11. Switch output sources ->No effect for input devices Mute/unmute status
12. Suspend & Resume ->No effect for input devices Mute/unmute status
13. Sudo reboot when MIC input is muted ->MIC keeps muted after boot up

## Expected results
* All devices should sound good
* Mute LED works good
* After suspend & resume, Mute LED should work as before
* After system reboot, Mute status should be same with reboot and Mute LED should work as before

