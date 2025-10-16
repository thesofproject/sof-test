#!/usr/bin/env python3

# Generates soundfile with given amount of channels.
# Every channel has a 2s sound, there is 1s pause between sounds. Every channel sound has a different frequency.
# Result file is saved as ~/Music/{num_channels}_channels_test.wav.
# Usage: python3 test-sound-generator.py <channels_nr>

import sys
import numpy as np
import soundfile as sf


SAMPLE_RATE = 48000
SOUND_DURATION = 2.0
SILENCE_DURATION = 1.0
DIR_PATH = "/home/ubuntu/Music/"


# Generates sound with given number of channels.
# Returns path of the result soundfile.
def generate_sound(channels_nr):
    frequency = 500
    
    sound_samples = int(SOUND_DURATION * SAMPLE_RATE)
    silence_samples = int(SILENCE_DURATION * SAMPLE_RATE)

    # Start sound quietly, gradually make it louder, and then make it quiet again.
    fade = np.linspace(0, 1, sound_samples // 2)
    fade_out = np.linspace(1, 0, sound_samples - len(fade))
    envelope = np.concatenate((fade, fade_out))

    total_samples = (sound_samples + silence_samples) * channels_nr
    multichannel = np.zeros((total_samples, channels_nr), dtype=np.float32)

    for ch in range(channels_nr):
        start = ch * (sound_samples + silence_samples)
        end = start + sound_samples

        t = np.linspace(0, SOUND_DURATION, sound_samples, endpoint=False)
        signal = 0.5 * np.sin(2 * np.pi * frequency * t) * envelope
        multichannel[start:end, ch] = signal

        frequency+=100 # Sound on every channel has a different frequency

    # Save result to file
    filepath = f"{DIR_PATH}{channels_nr}_channels_test.wav"
    sf.write(filepath, multichannel, SAMPLE_RATE, subtype="PCM_16")
    return filepath


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Incorrect arguments! Usage: python3 test-sound-generator.py <channels_nr>")
        sys.exit(1)

    ch_nr=int(sys.argv[1])

    file_path = generate_sound(ch_nr)
    print(f"Sound with {ch_nr} channels generated: {file_path}")

    sys.exit(0)
