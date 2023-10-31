set -e

# enable headset playback
amixer -c sofsoundwire cset name='Headphone Switch' on
amixer -c sofsoundwire cset name='rt711 FU05 Playback Volume' 80

# enable headset capture
amixer -c sofsoundwire cset name='Headset Mic Switch' on
amixer -c sofsoundwire cset name='rt711 FU0F Capture Switch' on
amixer -c sofsoundwire cset name='rt711 FU1E Capture Switch' on
amixer -c sofsoundwire cset name='rt711 FU0F Capture Volume' 30
amixer -c sofsoundwire cset name='rt711 FU1E Capture Volume' 30
