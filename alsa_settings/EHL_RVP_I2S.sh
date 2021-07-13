set -e

# enable headset playback
amixer -c sofehlrt5660 cset name='DAC1 MIXL DAC1 Switch' 1
amixer -c sofehlrt5660 cset name='DAC1 MIXR DAC1 Switch' 1
amixer -c sofehlrt5660 cset name='DAC1 MIXL Stereo ADC Switch' 0
amixer -c sofehlrt5660 cset name='DAC1 MIXR Stereo ADC Switch' 0
amixer -c sofehlrt5660 cset name='DAC1 Playback Volume' 50
amixer -c sofehlrt5660 cset name='PGA1.0 1 Master Playback Volume' 32
