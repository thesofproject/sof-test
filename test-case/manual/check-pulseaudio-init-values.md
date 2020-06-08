# Pulseaudio test - Initial mixer setting
Initial mixer settings should be set in UCM for system first boot up after install os, can find details in https://github.com/thesofproject/linux/issues/2067, especially for the mixer settings which can't be controller by pulseaduo

# Preconditions
1. PulseAudio should be enabled
2. UCM for the platform/device should be installed

# Test Description
* Install ubuntu OS, verify initial mixer settings is set in UCM and audio output and input work OK
* Using `alsactl init` to simulate system first boot up to vefiry initial amixer settings
* Pulseaudio souce input and output volume shouldn't be changed via normally system boot

## Test Case:
1. Install ubuntu os, `alsamixer` to verify all playback PGA volumes are set to 0db
2. `parecord 1.wav -vvv` to record audio then `paplay 1.wav -vvv` to play, both audio input and output work ok
3. Change all playback and capture PGA*.0 * volume to very low or mute via `alsamixer`
4. Run command `alsactl init` then `killall pulseaudio` to simulate the system first time boot up
5. `alsamixer` to verify all playback PGA volumes are set to 0db and repeat step2 to check audio input and output work ok
6. Change pulseaudio paplay volume during paplay from sound setting, eg. to about 30%
7. Change pulseaudio input source volume from sound setting. eg. to about 30%
8. Reboot system via `sudo reboot`
9. Open sound setting, to check pulseaduio paplay and input source volume are not changed, still about 30%
10. Connect Headset, repeat step3 to step 9, verify audio output and input via headset work ok
11. Disconnect Headset and connect HDMI, repeat step3 to step 9, verify audio outpt via HDMI and input via DMIC work ok

## Expected results
* Initial PGA volume is set and works

