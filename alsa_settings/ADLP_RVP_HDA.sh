set -e

# enable master
amixer -c sofhdadsp cset name='Master Playback Switch' 1
amixer -c sofhdadsp cset name='Master Playback Volume' 80

# enable headset
amixer -c sofhdadsp cset name='Headphone Playback Switch' 1
amixer -c sofhdadsp cset name='Headphone Playback Volume' 80

# enable pga volume
amixer -c sofhdadsp cset name='PGA1.0 1 Master Playback Volume' 32
