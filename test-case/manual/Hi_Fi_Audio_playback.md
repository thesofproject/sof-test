# High Fidelity Audio Rendering for 3.5mm JACK and USB-A/USB-C Endpoints in Linux
Verify High Fidelity Audio Rendering for 3.5mm JACK and USB-A/USB-C Endpoints in Linux

## Preconditions
1. The system is powered on.
2. A Linux-based system with 3.5mm audio JACK and USB-A/USB-C is available.
3. High-quality audio files for testing are available.
4. Ensure the appropriate audio topology file (96kHz/192kHz supported) is configured.

## Test Description
* Verification of high fidelity audio rendering for 3.5mm JACK and USB-A/USB-C endpoints in Linux.
* Playback should be smooth without any glitches or noise.

## Playback via 3.5mm JACK Headset
1. Clear the dmesg log:
    ```bash
    sudo dmesg -c
    ```
2. Plug the 3.5mm audio jack into the DUT.
3. Play a high-quality 96kHz audio file:
    ```bash
    time aplay -Dhw:0,0 -c 2 -r 96000 -f S24_LE /tmp/sample_96KHz.wav -d 10
    ```
4. Check the dmesg log:
    ```bash
    dmesg | grep -E "snd|sof|soc" | grep -i error
    ```
5. Play a high-quality 192kHz audio file:
    ```bash
    time aplay -Dhw:0,0 -c 2 -r 192000 -f S24_LE /tmp/sample_192KHz.wav -d 10
    ```
6. Check the dmesg log:
    ```bash
    dmesg | grep -E "snd|sof|soc" | grep -i error
    ```
7. Repeat steps 2-6 for USB-A/USB-C headsets.

## Expected Results
1. No audio-related errors observed in the dmesg log.
2. The 3.5mm JACK device should be listed.
3. Terminal output rate = 96000 and format = S24_LE, real time is nearly equal to mentioned playback duration (i,e. 10 sec)
4. No audio errors or failures should be present in the dmesg log.
5. Terminal output rate = 192000 and format = S24_LE, real time is nearly equal to mentioned playback duration (i,e. 10 sec)
6. No audio errors or failures should be present in the dmesg log.
7. Results should be the same as steps 2 to 6.
