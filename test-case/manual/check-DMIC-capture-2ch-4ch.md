# Check DMIC 2ch/4ch

Verification of 2ch/4ch DMIC recording 

## Preconditions
1. The system is powered on.
2. A Linux-based system with with PCH DMIC connected, ex:"Realtek AIOC and transducer card"

## Note
* This is specifically to test recording with PCH-connected DMIC


## Test Description
* Verification of 2ch/4ch DMIC recording 
* Recording should happen without any issue
* Playback should be smooth without any glitches or noise.

## Recording via 2ch/4ch DMIC
1. Verify dmic device list.
   ```bash
    arecord -l
    ```
2. Capture audio using dmic device:
    ```bash
    arecord -Dhw:0,0 -c 2 -r 48000 -f S24_LE -d 20 test.wav -vvv for 2Ch
    arecord -Dhw:0,6 -c 4 -r 48000 -f S32_LE -d 15 test3.wav -vvv for 4ch
    ```
3. Play and verify the audio file recorded in step 3:
    ```bash
    aplay -Dhw:0,0 -c 2 -r 48000 -f S24_LE test.wav -vvv 
    ```
   Note : 4ch dmic recording copy in IT laptop and play & verify 
    ```
4. Check the dmesg log:
    ```bash
    dmesg | grep -E "snd|sof|soc" | grep -i error
    ```


## Expected Results
1. DMIC devices should list
2. Audio capture should happen without any issues
3. Playback should be smooth without any glitch
4. No audio errors or failures should be present in the dmesg log.

