set -e

# enable headset playback
amixer -c sofsoundwire cset name='Headphone Switch' on
amixer -c sofsoundwire cset name='rt711 FU05 Playback Volume' 80

# override jack detection mode to headset
# related linux pr: https://github.com/thesofproject/linux/pull/4969
amixer -c sofsoundwire cset name='rt711 GE49 Selected Mode' 2 || true

# enable headset capture
amixer -c sofsoundwire cset name='Headset Mic Switch' on
amixer -c sofsoundwire cset name='rt711 FU0F Capture Switch' on
amixer -c sofsoundwire cset name='rt711 FU1E Capture Switch' on
amixer -c sofsoundwire cset name='rt711 FU0F Capture Volume' 25
amixer -c sofsoundwire cset name='rt711 FU1E Capture Volume' 25
