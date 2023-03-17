set -e

# enable headset playback
amixer -c sofsoundwire cset name='Headphone Switch' on
amixer -c sofsoundwire cset name='rt711 FU05 Playback Volume' 60

# enable headset capture
amixer -c sofsoundwire cset name='Headset Mic Switch' on
amixer -c sofsoundwire cset name='rt711 ADC 08 Capture Switch' on
amixer -c sofsoundwire cset name='rt711 ADC 08 Capture Volume' 25
