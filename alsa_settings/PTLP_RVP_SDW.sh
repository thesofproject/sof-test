set -e

#Enable "SoundWire microphones"
amixer -c sofsoundwire cset name='rt722 FU1E Capture Switch' 1

#Enable Speaker Switch
amixer -c sofsoundwire cset name='Speaker Switch' on
amixer -c sofsoundwire cset name='rt722 FU06 Playback Volume' 50

#Enable Headphone switch
amixer -c sofsoundwire cset name='Headphone Switch' on

# enable headset playback and capture
amixer -c sofsoundwire cset name='Headset Mic Switch' on
amixer -c sofsoundwire cset name='rt722 FU0F Capture Switch' 1
amixer -c sofsoundwire cset name='rt722 FU0F Capture Volume' 15
