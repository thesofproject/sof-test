set -e

# enable headset playback
amixer -c sofhdadsp cset name='Master Playback Switch' 1
amixer -c sofhdadsp cset name='Master Playback Volume' 50
amixer -c sofhdadsp cset name='Headphone Playback Switch' 1
amixer -c sofhdadsp cset name='Headphone Playback Volume' 87
amixer -c sofhdadsp cset name='PGA1.0 1 Master Playback Volume' 32

# enable HDMI
amixer -c sofhdadsp cset name='IEC958 Playback Switch' on
amixer -c sofhdadsp cset name='IEC958 Playback Switch',index=1  on
amixer -c sofhdadsp cset name='IEC958 Playback Switch',index=2  on
amixer -c sofhdadsp  cset name='PGA7.0 7 Master Playback Volume' 32
amixer -c sofhdadsp  cset name='PGA8.0 8 Master Playback Volume' 32
amixer -c sofhdadsp  cset name='PGA9.0 9 Master Playback Volume' 32
