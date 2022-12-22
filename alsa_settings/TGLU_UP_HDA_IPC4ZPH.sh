set -e

# enable headset playback
amixer -c sofhdadsp cset name='Master Playback Switch' on
amixer -c sofhdadsp cset name='Master Playback Volume' 45
amixer -c sofhdadsp cset name='gain.1.1 1 2nd Playback Volume' 45
amixer -c sofhdadsp cset name='gain.15.1 Deepbuffer Volume' 45
amixer -c sofhdadsp cset name='gain.2.1 2 Main Playback Volume' 45
