set -e

# enable headset playback
amixer -c sofhdadsp cset name='Master Playback Switch' 1
amixer -c sofhdadsp cset name='Master Playback Volume' 87
amixer -c sofhdadsp cset name='Headphone Playback Switch' 1
amixer -c sofhdadsp cset name='Headphone Playback Volume' 60

# enable headset capture
amixer -c sofhdadsp cset name='Capture Switch' on
amixer -c sofhdadsp cset name='Capture Volume' 30
