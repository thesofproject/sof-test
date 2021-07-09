# enable headset playback
amixer -c sofpcm512x cset name='Digital Playback Switch' 1
amixer -c sofpcm512x cset name='Digital Playback Volume' 150
amixer -c sofpcm512x cset name='PGA1.0 1 PCM 0 Playback Volume' 32
# set HDMI volume
amixer -c sofpcm512x cset name='IEC958 Playback Switch' on
amixer -c sofpcm512x cset name='IEC958 Playback Switch',index=1  on
amixer -c sofpcm512x cset name='IEC958 Playback Switch',index=2  on
amixer -c sofpcm512x cset name='PGA2.0 2 Master Playback Volume' 32
amixer -c sofpcm512x cset name='PGA3.0 3 Master Playback Volume' 32
amixer -c sofpcm512x cset name='PGA4.0 4 Master Playback Volume' 32
