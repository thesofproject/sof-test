
# Wov pipline trigger test
Wov pipline trigger testing for now.

# Preconditions
1. Wov-test.sh in wov-script folder.**Please check the script before run it to make sure use the right wov hw device id which match your platform.**
2. Test unit support wov test

# Test Description
* Change to different preamble/history via command worked on wov-test script.
* Change to fs16/24/32_le format via arecord command 

## Wov Test Case: 
#####1.check WoV with s16_le format 
1. Run command to start wov via "arecord -Dhw:0,$device_id -M -N -f s16_le -r 16000 -i -vvv -c2 --buffer-size=68000 ./tmp.wav" 
2. Clap hands or make some noise to trigger the wov after process starts.
3. Check the quality of recorded audio files.

#####2.Check WoV with s24_le format 
1. Run command to start wov via "arecord -Dhw:0,$device_id -M -N -f s24_le -r 16000 -i -vvv -c2 --buffer-size=68000 ./tmp.wav" 
2. Clap hands or make some noise to trigger the wov after process starts.
3. Check the quality of recorded audio files.

#####3.Check WoV with s32_le format 
1. Run command to start wov via "arecord -Dhw:0,$device_id -M -N -f s32_le -r 16000 -i -vvv -c2 --buffer-size=68000 ./tmp.wav" 
2. Clap hands or make some noise to trigger the wov after process starts.
3. Check the quality of recorded audio files.

#####4.Check WoV with different buffer sizes(must > 67200) 
1. Run command to start wov via "arecord -Dhw:0,$device_id -M -N -f s32_le -r 16000 -i -vvv -c2 --buffer-size=80000 ./tmp.wav" ** Note:The buffer size varies with different platform**
2. Clap hands or make some noise to trigger the wov after process starts.
3. Try different period size. eg.68000/70000/80000...
4. Check the quality of recorded audio files.

#####5.Check WoV with different period sizes(eg. 400/500/600...) 
1. Run with command "sudo su"
2. ./wov-test.sh -p 2100 -h 1800 -f s16_le -s 500 
3. Try different period sizes, and check the output period sizes if changed.
4. Clap hands or make some noise to trigger the wov after process starts.
5. Check the quality of recored audio files. 

#####6.Check WoV with different preamble sizes
1. Run with command "sudo su"
2. ./wov-test.sh -p 2100 -h 1800 -f s16_le
3. Try different preamble sizes, and check the output preamble sizes if changed.
4. Clap hands or make some noise to trigger the wov after process starts.
5. Check the quality of recored audio files.

#####7.Check WoV with different history depths
1. Run with command "sudo su"
2. ./wov-test.sh -p 2100 -h 1800 -f s16_le
3. Try different history depths, and check the output history depths if changed.
4. Clap hands or make some noise to trigger the wov after process starts 
5. Check the quality of recorded audio files.

#####8.Check WoV with different threadholds
1. wov test + headphone playback + headset capture.
2. wov test + headphone playback + Speaker playback + HDMI/DP playback 

## Expected results
* Wov can be triggerd successfully.
* Wov audio files quality is well.

