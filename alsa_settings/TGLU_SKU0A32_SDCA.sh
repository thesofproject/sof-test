set -e

# headset playback
amixer -c sofsoundwire cset name='Headphone Switch' 1
amixer -c sofsoundwire cset name='PGA1.0 1 Master Playback Volume' 32
amixer -c sofsoundwire cset name='rt711 FU05 Playback Volume' 55
amixer -c sofsoundwire cset name='rt711 FU44 Gain Volume' 0
