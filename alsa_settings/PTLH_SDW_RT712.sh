set -e

amixer -c sofsoundwire cset name='Headphone Switch' on
amixer -c sofsoundwire cset name='rt712 FU05 Playback Volume' 60
amixer -c sofsoundwire cset name='rt712 FU06 Playback Volume' 60

# enable headset playback and capture
amixer -c sofsoundwire cset name='Headset Mic Switch' on
amixer -c sofsoundwire cset name='rt712 FU0F Capture Switch' on
amixer -c sofsoundwire cset name='rt712 FU0F Capture Volume' 46
