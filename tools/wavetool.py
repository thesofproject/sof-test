#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2020 Intel Corporation. All rights reserved.

"""
A Tool to Generate and Manipulate Wave Files

Supported features:
- generate sinusoids
- give verdict in check-smart-amplifier test case by binary wave comparison
"""

import sys
import argparse
import numpy as np
import scipy.signal as signal
import scipy.io.wavfile as wavefile

# The acceptable threshold of smart amplifier delay, unit: ms.
# If the delay is longer, then DSP is overloaded or something
# is wrong with firmware scheduler.
SMART_AMP_DELAY_THRESHOLD = 8

# Module level global variable which will store command line parameters later
cmd = None

def generate_sine_mono(amp, freq, phase, fs, duration):
    """
    Generate mono sine wave.

    ``y(t) = A * sin(2 * pi * f * t + phi)``

    Parameters
    ----------
    amp: Amplitude, range: 0.0 ~ 1.0
    freq: Frequency, unit: Hertz
    phase: Initial Phase, unit: Radian
    fs: Sample rate, unit: Hertz
    duration: Duration, unit: Second

    Returns
    ----------
    Real 1-D Array
    """
    time = np.arange(0, duration, 1.0 / fs)
    return amp * np.sin(2 * np.pi * freq * time + phase)

def generate_wov():
    """
    Generate wave used in WoV test. This wave contains three parts:
    1. a low volume sine wave with default freq = 997.0 Hz which will not trigger WoV
    2. zero marker of 50ms
    3. a high volume sine wave with default freq = 997.0 Hz, which will trigger WoV
    """
    # a fixed 50ms zero marker
    zero_marker_time = 0.05
    amp = [cmd.amp[0], cmd.amp[0]] if len(cmd.amp) == 1 else cmd.amp
    freq = [cmd.freq[0], cmd.freq[0]] if len(cmd.freq) == 1 else cmd.freq
    phase = [cmd.phase[0], cmd.phase[0]] if len(cmd.phase) == 1 else cmd.phase
    duration = [cmd.duration[0], cmd.duration[0]] if len(cmd.duration) == 1 else cmd.duration
    wave_samples = int((zero_marker_time + sum(duration)) * cmd.sample_rate)

    sine_param1 = (amp[0], freq[0], phase[0], cmd.sample_rate, duration[0])
    mono_data1 = generate_sine_mono(*sine_param1)
    # extend channel
    sine_data1 = np.reshape(np.repeat(mono_data1, cmd.channel),[len(mono_data1), cmd.channel])

    sine_param2 = (amp[1], freq[1], phase[1], cmd.sample_rate, duration[1])
    mono_data2 = generate_sine_mono(*sine_param2)
    sine_data2 = np.reshape(np.repeat(mono_data2, cmd.channel),[len(mono_data2), cmd.channel])

    data = np.zeros((wave_samples, cmd.channel))
    data[0:sine_data1.shape[0]] = sine_data1
    data[wave_samples - sine_data2.shape[0]:wave_samples] = sine_data2
    return data

def generate_sinusoid():
    assert len(cmd.duration) == 1, "Each channel should have the same duration"
    wave_samples = int(cmd.duration[0] * cmd.sample_rate)
    wave_data = np.zeros((wave_samples, cmd.channel))
    for ch in range(cmd.channel):
        amp = cmd.amp[ch] if len(cmd.amp) == cmd.channel else cmd.amp[0]
        freq = cmd.freq[ch] if len(cmd.freq) == cmd.channel else cmd.freq[0]
        phase = cmd.phase[ch] if len(cmd.phase) == cmd.channel else cmd.phase[0]
        duration = cmd.duration[ch] if len(cmd.duration) == cmd.channel else cmd.duration[0]
        wave_data[:,ch] = generate_sine_mono(amp, freq, phase, cmd.sample_rate, duration)
    return wave_data

def generate_wav():
    if cmd.generate == 'sinusoid':
        wave_data = generate_sinusoid()
    elif cmd.generate == 'wov':
        wave_data = generate_wov()
    else:
        raise Exception('invalid generate function, will generate nothing')
    return wave_data

def save_wave(wave_data):
    wave_path = cmd.output
    if wave_path == '.' or not wave_path.endswith('wav'):
        wave_path = wave_path + '/tmp.wav'
    sample_bits = cmd.bits
    np_types = {'S8': np.int8, 'S16': np.int16, 'S32': np.int32}
    if sample_bits in np_types.keys():
        # range of wave_data is floating point [-1.0, 1.0]. When saving to any integer format use its full range.
        wave_data = (np.iinfo(np_types[sample_bits]).max * wave_data).astype(np_types[sample_bits])
    wavefile.write(wave_path, cmd.sample_rate, wave_data)

def do_wave_analysis():
    fs_wav, wave = wavefile.read(cmd.recorded_wave)
    if cmd.analyze == 'smart_amp':
        analyze_wav_smart_amp(wave, fs_wav)
    if cmd.analyze == 'wov':
        analyze_wav_wov(wave, fs_wav)

# remove digital zeros in two sides
def trim_wave(wave):
    # once waves go through DAC/ADC, zero will become small value close to zero,
    # here we set the digital zero threshold to 100, and cut samples below 100
    # of two sides, this has no negative impact to processing.
    zero_threshold_level = np.power(10, cmd.zero_threshold / 20.) * np.iinfo(wave.dtype).max
    wave_mono = wave[:,0]
    left_idx = 0
    right_idx = wave_mono.shape[0] - 1
    while True:
        if abs(wave_mono[left_idx]) > zero_threshold_level:
            break
        left_idx = left_idx + 1
        # the left index goes to the rightmost, then we may only have 0 in the recorded wave
        if left_idx == wave.shape[0] - 1:
            raise Exception("Recorded wave: volume too low or only contains zero")
    while True:
        if abs(wave_mono[right_idx]) > zero_threshold_level:
            break
        right_idx = right_idx - 1
    return wave[left_idx:right_idx,:], left_idx

# float point binary comparison is not supported, and will not be supported
# check recorded wave through smart amplifier component
def analyze_wav_smart_amp(wave, fs):
    trimed_ch_0_1, delay1 = trim_wave(wave[:,0:2])
    trimed_ch_2_3, delay2 = trim_wave(wave[:,2:4])
    samples_compare = min(trimed_ch_0_1.shape[0], trimed_ch_2_3.shape[0])
    is_bin_same = np.array_equal(trimed_ch_0_1[0:samples_compare,:], trimed_ch_2_3[0:samples_compare,:])
    smart_amp_delay = ((delay2 - delay1) / fs * 1000)

    print('Delay of smart amplifier is %0.3fms' % smart_amp_delay)
    if is_bin_same and smart_amp_delay < SMART_AMP_DELAY_THRESHOLD:
        print('Data of channel 0/1 is binary same as data of channel 2/3')
        print('Wave comparison result: PASSED')
    else:
        print('Data of channel 0/1 is not binary same as data of channel 2/3')
        print('Wave comparison result: FAILED')
        sys.exit(1001)

def find_zero_marker(wave, start, backward=False):
    # use a window of size 100 to find a rough zero marker index
    step = 100
    if backward:
        step = -step
    zero_threshold_level = np.power(10, cmd.zero_threshold / 20.) * np.iinfo(wave.dtype).max
    win = zero_threshold_level * np.ones(abs(step), dtype=wave.dtype)
    while not np.all(np.abs(wave[start:start + abs(step)]) < win):
        start = start + 2 * step # a jump of 200 samples will not jump over zero marker
        if (not backward and start > wave.shape[0] - 2 * abs(step)) or (backward and start < 2 * abs(step)):
            raise Exception('Zero marker not found')
    end = start
    while np.all(np.abs(wave[start:start + abs(step)]) < win) and start > 0:
        start = start - 1
    while np.all(np.abs(wave[end:end + abs(step)]) < win) and end + abs(step) < wave.shape[0]:
        end = end + 1
    return start, end + abs(step) - 1

def stdnotch(wave, fn, fs):
    target_q = 2.1
    b, a = signal.iirnotch(fn, target_q, fs)
    return signal.lfilter(b, a, wave, axis=0)

def normalize(data):
    max_val = np.iinfo(data.dtype).max
    return data / max_val

def analyze_wav_wov(wave, fs):
    """
    Specially designed wave are used in WoV test, see documentation of ``generate_wov``.
    We will filter out target freq and calculate THD+N value of low volume and high volume
    sine wave.
    """
    trimmed_wave, _ = trim_wave(wave)
    marker_start, marker_end = find_zero_marker(trimmed_wave[:,0], 0)
    if marker_end / fs > cmd.hb_time: # zero marker has to be in history buffer
        print('Zero marker not in history buffer')
        sys.exit(1002)
    x = normalize(trimmed_wave)
    low_vol_sine = x[0:marker_start,:]
    high_vol_sine = x[marker_end:,:]
    notch_freq = [cmd.freq[0], cmd.freq[0]] if len(cmd.freq) == 1 else cmd.freq
    low_vol_thdn = calc_thdn(low_vol_sine, fs, notch_freq[0])
    high_vol_thdn = calc_thdn(high_vol_sine, fs, notch_freq[1])
    print('THD+N of low volume sine wave: %s dB' % low_vol_thdn)
    print('THD+N of high volume sine wave: %s dB' % high_vol_thdn)
    thdn_pass = np.all(low_vol_thdn < cmd.threshold) and np.all(high_vol_thdn < cmd.threshold)
    if not thdn_pass:
        print('THD+N too high, wave analysis result: FAILED')
        sys.exit(1002)
    print('wave analysis result: PASSED')

def calc_thdn(wave, fs, freq):
    """
    This function calculates Total Harmonic Distortion plus Noise (THD+N) of a wave.

    Parameters
    ----------
    wave: Wave data from which THD+N will be calculated.
    fs: Sample rate of wave data
    freq: Frequency that will be removed before calculating THD+N

    Returns
    ----------
    A list of THD+N values for each channel
    """
    # skip 20ms to avoid the pulse due to filtering
    time_skip = 0.02
    samples_skip = int(time_skip * fs)
    filtered = stdnotch(wave, freq, fs)
    filtered_cut = filtered[samples_skip:,:]
    return 10 * np.log10(np.mean(np.power(filtered_cut, 2), axis=0))

def parse_cmdline():
    parser = argparse.ArgumentParser(add_help=True, formatter_class=argparse.RawTextHelpFormatter,
        description='A Tool to Generate and Manipulate Wave Files.')
    parser.add_argument('-v', '--version', action='version', version='%(prog)s 1.0')
    # wave parameters
    parser.add_argument('-g', '--generate', type=str, choices=['sinusoid', 'wov'], help='generate specified types of wave')
    parser.add_argument('-A', '--amp', type=float, nargs='+', default=[1.0], help='amplitude of generated wave')
    parser.add_argument('-F', '--freq', type=float, nargs='+', default=[997.0], help='frequency of generated wave')
    parser.add_argument('-P', '--phase', type=float, nargs='+', default=[0.0], help='phase of generated wave')
    parser.add_argument('-D', '--duration', type=float, nargs='+', default=[10.], help='duration of generated wave')
    parser.add_argument('-S', '--sample_rate', type=int, default=48000, help='sample rate of generated wave')
    parser.add_argument('-C', '--channel', type=int, default=2, help='channels of generated wave')
    parser.add_argument('-B', '--bits', type=str, choices=['S8', 'S16', 'S32', 'F32'], default='S16',
    help='sample bits of generated wave')
    parser.add_argument('-o', '--output', type=str, help='path to store generated files', default='.')
    # wave comparison arguments
    parser.add_argument('-a', '--analyze', type=str, choices=['smart_amp', 'wov'], help='analyze recorded wave to give case verdict')
    parser.add_argument('-R', '--recorded_wave', type=str, help='path of recorded wave')
    parser.add_argument('-Z', '--zero_threshold', type=float, default=-50.3, help='zero threshold in dBFS')
    parser.add_argument('-H', '--hb_time', type=float, default=2.1, help='history buffer size')
    parser.add_argument('-T', '--threshold', type=float, default=-65.0, help='expected threshold')
    return parser.parse_args()

def main():
    # Pylint discourage this usage, but we have to update global cmd in main()
    # pylint: disable=W0603
    global cmd
    cmd = parse_cmdline()

    if cmd.generate is not None:
        wave_data = generate_wav()
        save_wave(wave_data)

    if cmd.analyze is not None:
        do_wave_analysis()

if __name__ == '__main__':
    main()
