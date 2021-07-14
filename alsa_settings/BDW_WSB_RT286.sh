set -e

# enable headset playback
amixer -c rt286 cset name='HPO L Switch' 1
amixer -c rt286 cset name='HPO R Switch' 1
amixer -c rt286 cset name='Headphone Jack Switch' 1
amixer -c rt286 cset name='DAC0 Playback Volume' 75
amixer -c rt286 cset name='PGA1.1 1 Master Playback Volume' 32
