set -e

amixer -c sofsoundwire cset name='Headphone Switch' on
amixer -c sofsoundwire cset name='rt712 FU05 Playback Volume' 80
amixer -c sofsoundwire cset name='rt712 FU06 Playback Volume' 80

# enable headset playback and capture
amixer -c sofsoundwire cset name='Headset Mic Switch' on
amixer -c sofsoundwire cset name='rt712 FU0F Capture Switch' on
amixer -c sofsoundwire cset name='rt712 FU0F Capture Volume' 46

# set default volume levels
amixer -c sofsoundwire cset name='Pre Mixer Jack Out Playback Volume' 95%
amixer -c sofsoundwire cset name='Post Mixer Jack Out Playback Volume' 95%
amixer -c sofsoundwire cset name='Pre Mixer Deepbuffer Jack Out Volume' 95%
amixer -c sofsoundwire cset name='Pre Mixer Speaker Playback Volume' 95%
amixer -c sofsoundwire cset name='Post Mixer Speaker Playback Volume' 95%