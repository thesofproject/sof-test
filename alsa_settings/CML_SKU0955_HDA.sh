set -e

# set headset
amixer -c sofhdadsp cset name='Master Playback Switch' on
amixer -c sofhdadsp cset name='Master Playback Volume' 70
amixer -c sofhdadsp cset name='Capture Switch' on
amixer -c sofhdadsp cset name='Capture Volume' 20
amixer -c sofhdadsp cset name='Input Source' 0
amixer -c sofhdadsp cset name='PGA1.0 1 Master Playback Volume' 32
amixer -c sofhdadsp cset name='Headphone Playback Volume' 70
amixer -c sofhdadsp cset name='Headphone Mic Boost Volume' 1
amixer -c sofhdadsp cset name='Headphone Playback Switch' on
amixer -c sofhdadsp cset name='Speaker Playback Switch' off

# set HDMI
amixer -c sofhdadsp cset name='IEC958 Playback Switch' on
amixer -c sofhdadsp cset name='IEC958 Playback Switch',index=1  on
amixer -c sofhdadsp cset name='IEC958 Playback Switch',index=2  on
amixer -c sofhdadsp cset name='PGA3.0 3 Master Playback Volume' 32
amixer -c sofhdadsp cset name='PGA7.0 7 Master Playback Volume' 32
amixer -c sofhdadsp cset name='PGA8.0 8 Master Playback Volume' 32
