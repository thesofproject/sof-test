# enable headset playback
amixer -c sofcmlrt1011rt5 cset name='DAC L Mux' 0
amixer -c sofcmlrt1011rt5 cset name='DAC R Mux' 0
amixer -c sofcmlrt1011rt5 cset name='HPOL Playback Switch' 1
amixer -c sofcmlrt1011rt5 cset name='HPOR Playback Switch' 1
amixer -c sofcmlrt1011rt5 cset name='Stereo1 DAC MIXL DAC L1 Switch' 1
amixer -c sofcmlrt1011rt5 cset name='Stereo1 DAC MIXR DAC R1 Switch' 1
amixer -c sofcmlrt1011rt5 cset name='PGA1.0 1 Master Playback Volume' 32
amixer -c sofcmlrt1011rt5 cset name='DAC1 Playback Volume' 60

# enable headset capture
amixer -c sofcmlrt1011rt5 cset name='STO1 ADC Capture Switch' 1
amixer -c sofcmlrt1011rt5 cset name='RECMIX1L CBJ Switch' 1
amixer -c sofcmlrt1011rt5 cset name='IF1 01 ADC Swap Mux' 2
amixer -c sofcmlrt1011rt5 cset name='CBJ Boost Volume' 0
amixer -c sofcmlrt1011rt5 cset name='Stereo1 ADC L Mux' 0
amixer -c sofcmlrt1011rt5 cset name='Stereo1 ADC L1 Mux' 1
amixer -c sofcmlrt1011rt5 cset name='Stereo1 ADC R1 Mux' 1
amixer -c sofcmlrt1011rt5 cset name='Stereo1 ADC MIXL ADC2 Switch' 0
amixer -c sofcmlrt1011rt5 cset name='Stereo1 ADC MIXR ADC2 Switch' 0
amixer -c sofcmlrt1011rt5 cset name='Stereo1 ADC MIXL ADC1 Switch' 1
amixer -c sofcmlrt1011rt5 cset name='Stereo1 ADC MIXR ADC1 Switch' 1

# enable HDMI
amixer -c sofcmlrt1011rt5 cset name='PGA4.0 4 Master Playback Volume' 32
amixer -c sofcmlrt1011rt5 cset name='PGA5.0 5 Master Playback Volume' 32

