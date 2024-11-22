# High Fidelity Audio render for 3.5mm JACK and USB-A/USB-C endpoints
Hi-Fi 24Hz 96/192KHz audio playback using 3.5mm JACK and USB-A/USB-C endpoints

# Preconditions
1. System is powered on.
2. download audio files from cloud share point: https://intel-my.sharepoint.com/:f:/r/personal/hariprasad_rajendra_intel_com/Documents/Test_Media?csf=1&web=1&e=oC5fGF
	jazz-96kHz-24bit.flac and slow-motion_24bit-192khz.flac

# Test Description
* Play Hi-Fi 24Hz 96/192KHz audio on 3.5mm JACK endpoint
* Playback should smooth with any glitches/noise
* Repeat same on USB endpoint

## Playback via 3.5mm JACK Headset
1. Clear Dmesg log
	"sudo dmesg -c"
2. Plug 3.5mm headset into applicable JACK and check the endpoints enemuration
	"aplay -l"
3. Notedown the JACK card and device details
	default case "card:0 and device:0" is sync with JACK
4. Play Hi-Fi audio file on JACK hardware device
	"aplay -Dhw:0,0 -c 2 -r 192000 -F S24_LE slow-motion_24bit-192khz.flac"
5. Listen audio playback via headset
6. Check dmesg log
7. Repeat step 1-5 for USB-A/USB-C Headset

## Expect result
1. No audio related error observation in dmesg log
2. 3.5mm JACK device should list 
4. Playback should run smooth without any failure messages
5. No noise/glitches sound hear from speakers during playback
6. No audio related error observation in dmesg log
