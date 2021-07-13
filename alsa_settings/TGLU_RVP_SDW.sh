set -e

# enable playback
amixer -c sofsoundwire cset name='Headphone Switch' on
amixer -c sofsoundwire cset name='PGA1.0 1 Master Playback Volume' 32
amixer -c sofsoundwire cset name='rt711 DAC Surr Playback Volume' 55
