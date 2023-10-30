set -e

# enable headset playback
amixer -c sofhdadsp cset name='Master Playback Switch' 1
amixer -c sofhdadsp cset name='Master Playback Volume' 80
amixer -c sofhdadsp cset name='Headphone Playback Switch' 1
amixer -c sofhdadsp cset name='Headphone Playback Volume' 80
# enable headset capture
amixer -c sofhdadsp cset name='Headphone Mic Boost Volume' 0
amixer -c sofhdadsp cset name='Headset Mic Boost Volume' 0
amixer -c sofhdadsp cset name='Capture Volume' 30
