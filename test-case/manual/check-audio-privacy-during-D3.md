# Verify audio privacy (hard mute) functionality during DSP D3 state
Verify audio privacy (hard mute) functionality when DSP is in D3 state

## Preconditions
1. The RVP must have active audio endpoints.
2. The RVP must have a functional hard mute switch or toggle.
3. Enable BIOS settings:
   * Microphone Privacy Mode = "HW managed Microphone Privacy"
   * Enable corresponding codec options, e.g., SNDW#3 [x] for SoundWire.
   * Enable DMIC option, e.g., DMIC [x] for DMIC
4. Make sure UCM is up to date
   * Copy the ucm and ucm2 trees to the alsa-lib configuration directory (usually located in /usr/share/alsa) including symlinks
   * Reference: https://github.com/alsa-project/alsa-ucm-conf/

## Test Description
* Verification of audio privacy (hard mute) functionality during DSP D3 state (suspended) in linux system.
* Must not capture audio samples when the audio privacy switch is turned ON when DSP was in D3 state.
* Must capture audio samples when the audio privacy switch is turned OFF when DSP was in D3 state.

## Steps to Execute
1. System is booted in the OS
2. Run command in second terminal to monitor changes of DSP state via command:
    ```bash
    ./sof-test/tools/sof-dump-status.py --dsp_status 0
    ```
    By default DSP is "suspended" and after interrupt (play or record new wav file, DSP wakes up and is in "active" state)
3. Make sure that DSP is "suspended", then turn ON the audio privacy switch. Led indicator must be turned ON.
4. Capture audio via 3.5mm jack ports:
    ```bash
    arecord -Ddefault -c 2 -r 48000 -f S16_LE /tmp/test_sample_mute_during_d3.wav -vvv
    ```
5. Check if DSP was in "active" state during recording, then check on the file if audio was muted in any application to verify sound (for example Audacity).
6. Make sure that DSP is in "suspended" state, then turn OFF the audio privacy switch. Led indicator must be turned OFF.
7. Capture audio via 3.5mm jack ports:
    ```bash
    arecord -Ddefault -c 2 -r 48000 -f S16_LE /tmp/test_sample_unmute_during_d3.wav -vvv
    ```
8. Check if DSP was in "active" state during recording, then check on the file if audio was not muted in any application to verify sound (for example Audacity).
9. Check for errors: 
    ```bash
    journalctl -b -p 4.
    ```
## Expected Results
1. No errors in `journalctl -b -p 4`, jack device must be visible in system.
2. DSP must be in "suspended" state.
3. Recording must start without problems.
4. The MIC mute LED must glow.
5. During recording DSP must be in "active" state, after recording, audio must be muted.
6. DSP must be in "suspended" state.
7. The MIC mute LED must turn OFF.
8. Recording must start without problems.
9. During recording DSP must be in "active" state, after recording, audio must be unmuted
10. No audio errors or failures must be present in the 'journalctl -b -p 4'.