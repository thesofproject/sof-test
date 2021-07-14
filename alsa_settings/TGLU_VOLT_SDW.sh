set -e

# headset playback
amixer -c sofsoundwire cset name='Headphone Switch' 1
amixer -c sofsoundwire cset name='rt5682 DAC L Mux' 1
amixer -c sofsoundwire cset name='rt5682 DAC R Mux' 1
amixer -c sofsoundwire cset name='rt5682 HPOL Playback Switch' 1
amixer -c sofsoundwire cset name='rt5682 HPOR Playback Switch' 1
amixer -c sofsoundwire cset name='rt5682 Stereo1 DAC MIXL DAC L1 Switch' 1
amixer -c sofsoundwire cset name='rt5682 Stereo1 DAC MIXR DAC R1 Switch' 1
amixer -c sofsoundwire cset name='rt5682 DAC1 Playback Volume' 60
amixer -c sofsoundwire cset name='PGA1.0 1 Master Playback Volume' 32

# headset capture
amixer -c sofsoundwire cset name='rt5682 STO1 ADC Capture Switch' 1
amixer -c sofsoundwire cset name='rt5682 RECMIX1L CBJ Switch' 1
amixer -c sofsoundwire cset name='rt5682 IF1 01 ADC Swap Mux' 2
amixer -c sofsoundwire cset name='rt5682 CBJ Boost Volume' 3
amixer -c sofsoundwire cset name='rt5682 Stereo1 ADC L Mux' 0
amixer -c sofsoundwire cset name='rt5682 Stereo1 ADC L1 Mux' 1
amixer -c sofsoundwire cset name='rt5682 Stereo1 ADC R1 Mux' 1
amixer -c sofsoundwire cset name='rt5682 Stereo1 ADC MIXL ADC2 Switch' 0
amixer -c sofsoundwire cset name='rt5682 Stereo1 ADC MIXR ADC2 Switch' 0
amixer -c sofsoundwire cset name='rt5682 Stereo1 ADC MIXL ADC1 Switch' 1
amixer -c sofsoundwire cset name='rt5682 Stereo1 ADC MIXR ADC1 Switch' 1

