set -e

# SSP playback
amixer -c sofnocodec cset name='gain.1.1 Playback Volume 1' 45
amixer -c sofnocodec cset name='gain.15.1 Deepbuffer Volume' 45
amixer -c sofnocodec cset name='gain.2.1 Main Playback Volume 2' 45
amixer -c sofnocodec cset name='gain.3.1 Playback Volume 3' 45
amixer -c sofnocodec cset name='gain.4.1 Main Playback Volume 4' 45
amixer -c sofnocodec cset name='gain.5.1 Playback Volume 5' 45
amixer -c sofnocodec cset name='gain.6.1 Main Playback Volume 6' 45

# SSP capture
amixer -c sofnocodec cset name='gain.17.1 Main Capture Volume 2' 45
amixer -c sofnocodec cset name='gain.7.1 Main Capture Volume 1' 45
amixer -c sofnocodec cset name='gain.8.1 Host Capture Volume' 45
