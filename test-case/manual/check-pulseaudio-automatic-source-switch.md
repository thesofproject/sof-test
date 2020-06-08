# Pulseaudio test - Automatic source switch
Ouput and input sources should be automatic changed once an external device is connected or disconnected

# Preconditions
1. PulseAudio should be enabled
2. UCM for the platform/device should be installed

# Test Description
* Output source and intput source should be automatic changed once connect or disconnect headset
* Output source should be automatic changed once connect or disconnect HDMI

## Headset Test Case:
1. Boot up system without HDMI and headset connection
2. `parecord 1.wav -vvvv`, build-in device, such as DMIC is used for capturing. Say something then ctrl+c to stop
3. `paplay 1.wav -vvvv`, internal speaker is used for playback. Audio is output successfully then press ctrl+c to stop
4. Wait for about 3s till runtime PM is suspended, can check via `cat "/sys/bus/pci/devices/0000:00:1f.3/power/runtime_status"`, the pci device id can be find from `lspci` for Multimedia audio controller
5. Plug in headset
6. `parecord 2.wav -vvvv`, headset Mic is used for capturing. Say something then ctrl+c to stop
7. `paplay 2.wav -vvvv`, headphone is used for playback. No audio output on internal speaker
8. Unplug headset
9. `parecord 3.wav -vvvv`, DMIC is used for capturing. Say something then ctrl+c to stop
10. `paplay 4.wav -vvvv`, internal speaker is used for playback normally
11. Plug in headset, then `sudo reboot` with headset connection
12. Open sound settting, check headphone is output source, headset Mic is input source
13. Check paplay and parecord works OK
14. Keep sound setting open, Repeat step 8 to step11 to do plug and unplug headset actions, both output and input sources are automatically switched succesfully
15. One termally start paplay, another terminal start parecord, do headset plug in and unplug actions during paplay and parecord, both output and input sources are automaticlly swtiched successfully

## HDMI/DP Test Case:
1. Boot up system without HDMI and headset connection
2. `parecord 1.wav -vvvv`, build-in device, such as DMIC is used for capturing. Say something then ctrl+c to stop
3. `paplay 1.wav -vvvv`, internal speaker is used for playback. Audio is output successfully then press ctrl+c to stop
4. Wait for about 3s till runtime PM is suspended, can check via `cat "/sys/bus/pci/devices/0000:00:1f.3/power/runtime_status"`
5. Plug in HDMI/DP
6. Open sound setting, check Output source is switched to HDMI/DP. Close sound setting
7. `parecord 2.wav -vvvv`, DIMC is used for capturing. Say something then ctrl+c to stop
8. `paplay 2.wav -vvvv`, HDMI/DP is used for playback. No audio output on internal speaker
9. Unplug HDMI/DP
10. `parecord 3.wav -vvvv`, DMIC is used for capturing. Say something then ctrl+c to stop
11. `paplay 4.wav -vvvv`, internal speaker is used for playback normally
12. Plug in HDMI again, `paplay 2.wav -vvvv`, HDMI/DP is used for playback automaticlly. No audio output on internal speaker
13. `sudo reboot` with HDMI/DP connection
14. Open sound settting, check HDMI/DP is output source, DMIC is input source
15. Check paplay and parecord work OK
16. Keep sound setting open, Repeat step 9 to step 12 to do unplug and plug HDMI/DP actions, output source is automatically switched between HDMI/DP and internal speaker succesfully
17. One termally start paplay, another terminal start parecord, do HDMI/DP plug in and unplug actions during paplay and parecord, outpu source is automaticlly swtiched successfully

## Headset and HDMI/DP Test Case:
1. Boot up system without HDMI and headset connect
2. Plug in HDMI/DP
3. Open sound setting, check Output source is auto switched to HDMI/DP. Close sound setting
4. Plug in headset
5. Open sound setting, Output source is auto switched to headset, Input source is headset MIC
6. Unplug headset, both output source and input source are auto switched
7. Plug in headset, both output source and input soruce are auto switched
8. Unplug HDMI, output source and input source isn't changed.
9. Plug in HDMI again, output soruce is auto switched to HDMI/DP, Input source is DMIC
10. `parecord 3.wav -vvvv`, DMIC is used for capturing. Say something then ctrl+c to stop
11. `paplay 4.wav -vvvv`, HDMI is used for playback normally
12. Unplug HDMI/DP, output souce is auto switched
13. `sudo reboot` with both  HDMI/DP and headset connection
14. Open sound settting, check HDMI/DP is output source

## Expected results
* Should automaticlly swith to headset once plug in heaset and swith back to internal speaker and DMIC once unplug headset
* Should automaticlly switch to HDMI/DP once plug in HDMI /DP and switch back to headset /internal speaker once unplug HDMI/DP

