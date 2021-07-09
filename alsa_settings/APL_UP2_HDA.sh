# set HDMI volume
amixer -c sofhdadsp cset name='IEC958 Playback Switch' on
amixer -c sofhdadsp cset name='IEC958 Playback Switch',index=1  on
amixer -c sofhdadsp cset name='IEC958 Playback Switch',index=2  on
amixer -c sofhdadsp cset name='PGA2.0 2 Master Playback Volume' 32
amixer -c sofhdadsp cset name='PGA3.0 3 Master Playback Volume' 32
amixer -c sofhdadsp cset name='PGA4.0 4 Master Playback Volume' 32
