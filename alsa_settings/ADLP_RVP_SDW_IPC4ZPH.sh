set -e

# enable playback
amixer -c sofsoundwire cset name='Headphone Switch' on
amixer -c sofsoundwire cset name='gain.0.1 1 Playback Volume 0' 45
amixer -c sofsoundwire cset name='gain.15.1 Deepbuffer Volume' 45
amixer -c sofsoundwire cset name='gain.1.1 2 Main Playback Volume' 45
amixer -c sofsoundwire cset name='rt711 DAC Surr Playback Volume' 80
