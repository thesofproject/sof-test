set -e

# enable headset playback
amixer -c sofglkda7219max cset name='Headphone Gain Ramp Switch' 1
amixer -c sofglkda7219max cset name='Headphone Volume' 35 35
amixer -c sofglkda7219max cset name='Headphone Switch' 1
amixer -c sofglkda7219max cset name='Headphone ZC Gain Switch' 0
amixer -c sofglkda7219max cset name='Headphone Jack Switch' 1
amixer -c sofglkda7219max cset name='Playback Digital Volume' 111 111
amixer -c sofglkda7219max cset name='Playback Digital Switch' 1
amixer -c sofglkda7219max cset name='Playback Digital Gain Ramp Switch' 1
amixer -c sofglkda7219max cset name='Out DACR Mux' 3
amixer -c sofglkda7219max cset name='Out DAIR Mux' 0
amixer -c sofglkda7219max cset name='Mixer Out FilterL DACL Switch' 1
amixer -c sofglkda7219max cset name='Mixer Out FilterR DACR Switch' 1 10
amixer -c sofglkda7219max cset name='PGA1.0 1 Master Playback Volume' 32

# set HDMI volume
amixer -c sofglkda7219max cset name='IEC958 Playback Switch' on
amixer -c sofglkda7219max cset name='IEC958 Playback Switch',index=1  on
amixer -c sofglkda7219max cset name='IEC958 Playback Switch',index=2  on
amixer -c sofglkda7219max cset name='PGA2.0 2 Master Playback Volume' 32
amixer -c sofglkda7219max cset name='PGA5.0 5 Master Playback Volume' 32
amixer -c sofglkda7219max cset name='PGA6.0 6 Master Playback Volume' 32
