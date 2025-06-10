# Verify audio privacy (hard mute) functionality during D3 state
Verify audio privacy (hard mute) functionality in Linux in D3 state

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
* Verification of audio privacy (hard mute) functionality during suspension in D3 state in linux system.
* Should not capture audio samples when the audio privacy switch is turned ON during D3 state.
* Should capture audio samples when the audio privacy switch is turned OFF during D3 state.

## Steps to Execute
1. System is booted in the OS
2. Capture audio via 3.5mm jack ports:
    ```bash
    arecord -Dhw:0,0 -c 2 -r 48000 -f S16_LE /tmp/test_sample_mute_during_d3.wav -vvv
    ```
3. Enter D3 state via command:
    ```bash
    sudo rtcwake -m mem --seconds 30
    ```
4. Turn ON the audio privacy switch. Led indicator should be turned ON.
5. Exit D3 state, check on the file if audio was muted in D3 state
6. Capture audio via 3.5mm jack ports:
    ```bash
    arecord -Dhw:0,0 -c 2 -r 48000 -f S16_LE /tmp/test_sample_unmute_during_d3.wav -vvv
    ```
7. Enter D3 state via command:
    ```bash
    sudo rtcwake -m mem --seconds 30
    ```
8. Turn OFF the audio privacy switch. Led indicator should be turned OFF.
9. Exit D3 state, check on the file if audio was unmuted in D3 state
10. Check the dmesg log.

## Expected Results
1. No dmesg errors, jack device should be visible in system.
2. Recording should start without problems.
3. Device should enter D3 state.
4. The MIC mute LED should glow.
5. The microphone is completely disabled during D3 state, and no audio is captured or transmitted.
6. Recording should start without problems.
7. Device should enter D3 state.
8. The MIC mute LED should turn OFF.
9. The microphone is completely enabled during D3 state, resuming normal functionality, capturing and transmitting audio.
10. No audio errors or failures should be present in the dmesg log.
