set -e

# enable headset playback
amixer -c sofhdadsp cset name='Master Playback Switch' 1
amixer -c sofhdadsp cset name='Master Playback Volume' 87
amixer -c sofhdadsp cset name='Headphone Playback Switch' 1
amixer -c sofhdadsp cset name='Headphone Playback Volume' 60
amixer -c sofhdadsp cset name='gain.1.1 1 2nd Playback Volume' 45
amixer -c sofhdadsp cset name='gain.2.1 2 Main Playback Volume' 45
amixer -c sofhdadsp cset name='gain.5.1 5 3nd Playback Volume' 45
