set -e

# set headset
amixer -c sofsoundwire cset name='Headphone Switch' 1
amixer -c sofsoundwire cset name='PGA1.0 1 Master Playback Volume' 32
amixer -c sofsoundwire cset name='rt711 FU05 Playback Volume' 52
