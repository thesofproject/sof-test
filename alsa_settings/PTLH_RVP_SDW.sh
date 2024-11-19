set -e

# enable headset playback and capture
amixer -c sofsoundwire cset name='Headset Mic Switch' on
amixer -c sofsoundwire cset name='rt722 FU0F Capture Switch' on
amixer -c sofsoundwire cset name='rt722 FU0F Capture Volume' 50
