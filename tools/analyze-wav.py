"""
Detect glitches (vertical lines) in a spectrogram of a WAV file.
Usage: python analyze-wav.py <path_to_wav_file>
The script reads the WAV file, computes its spectrogram,
and identifies time points where vertical lines (broadband events) occur.
The audio's first and last 0.5 seconds are trimmed to avoid edge artifacts.

The vertical lines are computed the following way:
1. Trim silence from the start and end of the audio.
2. Trim 0.5 seconds from the start and end of the audio to avoid edge artifacts.
3. Compute the spectrogram of the audio signal.
4. Normalize the spectrogram per frequency bin to [0, 1].
5. For each time slice, determine the fraction of frequency bins that are "active"
   (i.e., have normalized values above a certain threshold).
6. If the fraction of active frequency bins exceeds a predefined threshold,
   mark that time slice as containing a vertical line.

We define active_freqs instead of just calculating the average normalised energy
value to avoid a situation, where few very loud frequencies dominate the average.

Output:
- Prints detected glitch timestamps (in seconds)
- Returns 1 (exit code) if glitches are detected, 0 if sound is clean.
"""

import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import spectrogram 
import soundfile as sf


def get_dtype(subtype):
    if 'pcm_16' in subtype:
        return 'int16'
    elif 'pcm_24' in subtype:
        return 'int32'  # soundfile uses int32 for 24-bit PCM
    elif 'pcm_32' in subtype:
        return 'int32'
    elif 'ulaw' in subtype or 'mulaw' in subtype:
        return 'int16'
    elif 'alaw' in subtype:
        return 'int16'
    else:
        return 'float32'  # fallback for unknown or float encodings


def detect_vertical_lines(wav_file):
    info = sf.info(wav_file)
    dtype = get_dtype(info.subtype.lower())
    
    data, sr = sf.read(wav_file, dtype=dtype)
    if data.ndim > 1:
        data = data[:, 0]
    # Remove silence at the beginning and end
    silence_threshold = 0.01 
    abs_data = np.abs(data)
    mean_amp = abs_data.mean()
    threshold = silence_threshold * mean_amp
    non_silent = np.where(abs_data > threshold)[0]
    if non_silent.size == 0:
        print("No non-silent audio detected.")
    else:
        print(f"Non-silent audio from {non_silent[0]/sr:.2f}s to {non_silent[-1]/sr:.2f}s")
    start_idx = non_silent[0]
    end_idx = non_silent[-1] + 1
    data = data[start_idx:end_idx]
    # Trim beginning and end
    trim_duration_sec = 0.2
    trim_samples = int(trim_duration_sec * sr)
    if len(data) <= 2 * trim_samples:
        print("Audio file too short after trimming.")
        return []

    data = data[trim_samples:-trim_samples]

    f, t, Sxx = spectrogram(data, sr)
    Sxx_dB = 10 * np.log10(Sxx + 1e-10)

    # Normalize per frequency bin to [0, 1]
    Sxx_norm = (Sxx_dB - np.min(Sxx_dB, axis=1, keepdims=True)) / (
        np.ptp(Sxx_dB, axis=1, keepdims=True) + 1e-10
    )
    freq_threshold = 0.6
    # If the normalised frequency is greater than the threshold, mark it as active.
    active_freqs = Sxx_norm > freq_threshold
    coverage = np.sum(active_freqs, axis=0) / active_freqs.shape[0]
    coverage_threshold = 0.8
    # If coverage exceeds threshold, mark as vertical line.
    vertical_lines = np.where(coverage > coverage_threshold)[0]
    print(f"Detected possible glitches at time indices: {vertical_lines + trim_samples + non_silent[0]}")
    print(f"Corresponding times (s): {t[vertical_lines] + trim_duration_sec + non_silent[0]/sr}")
    return vertical_lines

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python analyze-wav.py <path_to_wav_file>")
        sys.exit(1)

    result = detect_vertical_lines(sys.argv[1])
    sys.exit(1 if result.any() else 0)
