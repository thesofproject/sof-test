set -e

# SSP playback
amixer -c sofnocodec cset name='PGA1.1 1 Master Playback Volume' 32
amixer -c sofnocodec cset name='PGA3.0 3 Master Playback Volume' 32

# SSP capture
amixer -c sofnocodec cset name='PGA2.0 2 Master Capture Switch' on
amixer -c sofnocodec cset name='PGA2.0 2 Master Capture Volume' 50

amixer -c sofnocodec cset name='PGA4.0 4 Master Capture Volume' 50
