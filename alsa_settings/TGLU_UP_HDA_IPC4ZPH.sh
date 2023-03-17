set -e

# enable headset playback
amixer -c sofhdadsp cset name='Master Playback Switch' on
amixer -c sofhdadsp cset name='Master Playback Volume' 45

# enable headset capture
amixer -c sofhdadsp cset name='Capture Switch' on
amixer -c sofhdadsp cset name='Capture Volume' 30
