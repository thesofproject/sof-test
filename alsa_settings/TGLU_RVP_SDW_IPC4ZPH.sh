set -e

# enable headset playback
amixer -c sofsoundwire cset name='Headphone Switch' on
amixer -c sofsoundwire cset name='rt711 DAC Surr Playback Volume' 55

# enable headset capture
amixer -c sofsoundwire cset name='Headset Mic Switch' on
amixer -c sofsoundwire cset name='rt711 ADC 08 Capture Switch' on
amixer -c sofsoundwire cset name='rt711 ADC 08 Capture Volume' 45
amixer -c sofsoundwire cset name='rt711 AMIC Volume' 0
