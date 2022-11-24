set -e

# enable playback
amixer -c sofsoundwire cset name='Headphone Switch' on
amixer -c sofsoundwire cset name='rt711 FU05 Playback Volume' 60
amixer -c sofsoundwire cset name='gain.1.1 1 Playback Volume 0' 45
amixer -c sofsoundwire cset name='gain.2.1 2 Main Playback Volume' 45
amixer -c sofsoundwire cset name='gain.5.1 5 2nd Playback Volume' 45
