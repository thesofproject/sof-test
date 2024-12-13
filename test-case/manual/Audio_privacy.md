# Verify Audio Privacy (Hard Mute) Functionality
Verify Audio Privacy (Hard Mute) Functionality in Linux

## Preconditions
1. The RVP should have active audio endpoints.
2. The RVP should have a functional hard mute switch or toggle.
3. Enable BIOS settings:
   * Microphone Privacy Mode = "HW managed Microphone Privacy"
   * Enable corresponding codec options, e.g., SNDW#3 [x] for SoundWire.
   * Enable DMIC option, e.g., DMIC [x] for DMIC
4. Make sure UCM is up to date
   * Copy the ucm and ucm2 trees to the alsa-lib configuration directory (usually located in /usr/share/alsa) including symlinks
   * Reference: https://github.com/alsa-project/alsa-ucm-conf/ 

## Test Description
* Verification of audio privacy (hard mute) functionality in a Linux system.
* Should not capture audio samples when the audio privacy switch is turned ON.

## Steps to Execute
1. Turn ON the audio privacy switch. Refer to RVP TOPS documents to find the switch location.
    Example: Switch identification mentioned as "MIC_privacy_SW_IN".
2. Capture audio via 3.5mm jack ports:
    ```bash
    arecord -Dhw:0,0 -c 2 -r 48000 -f S16_LE /tmp/test_sample_mute.wav -vvv
    ```
3. Verify the playback for the capture in step 2:
    ```bash
    aplay -Dhw:0,0 -c 2 /tmp/test_sample_mute.wav -vvv
    ```
4. Turn OFF the audio privacy switch.
5. Capture audio via 3.5mm jack ports:
    ```bash
    arecord -Dhw:0,0 -c 2 -r 48000 -f S16_LE /tmp/test_sample_unmute.wav -vvv
    ```
6. Verify the playback for the capture in step 5:
    ```bash
    aplay -Dhw:0,0 -c 2 /tmp/test_sample_unmute.wav -vvv
    ```
7. Repeat steps 2 and 6 for USB-A/USB-C endpoints.
8. Repeat steps 2 to 7 using PulseAudio or PipeWire sound server.
9. Check the dmesg log.
10. Repeat Step 1 to 9 for DMIC (Update DMIC Audio card instead of JACK e.g. "-Dhw:0,6" ) 

## Expected Results
1. The MIC mute LED should glow.
2. The microphone is completely disabled, and no audio is captured or transmitted.
3. The playback should not contain audio samples.
4. The MIC mute LED should turn OFF.
5. The microphone is completely enabled, resuming normal functionality, capturing and transmitting audio.
6. The playback should contain audio samples.
7. Results should be the same as steps 2 to 6.
8. Results should be the same as steps 2 to 7.
9. No audio errors or failures should be present in the dmesg log.
