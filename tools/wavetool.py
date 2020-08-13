#! /usr/bin/python3
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2020 Intel Corporation. All rights reserved.

"""
A Tool to Generate and Manipulate Wave Files

Supported features:
- generate sinusoids
- give verdict in check-smart-amplifier test case by binay wave comparison
"""

import os
import sys
import argparse
import numpy as np
import scipy.signal as signal
import scipy.io.wavfile as wavefile

# The acceptable threshold of smart amplifier delay, unit: ms.
# If the dealy is longer, then DSP is overloaded or something
# is wrong with firmware scheduler.
SMART_AMP_DELAY_THRESHOLD = 5

def generate_sinusoids(**p):
    """
    Generate sine or cosine wave.

    ``y(t) = A * sin(2 * pi * f * t + phi)``

    ``y(t) = A * cos(2 * pi * f * t + phi)``

    Parameters
    ----------
    dict of sinusiod parameters:
    p['type']: Wave type, ``sine`` or ``cosine``
    p['amp']: Amplitude, range: 0.0 ~ 1.0
    p['freq']: Frequency, unit: Herz
    p['phase']: Phase, unit: Radian
    p['chan']: Channels
    p['sample_rate']: Sample rate, unit: Herz
    p['duration']: Duration, unit: Second

    Returns
    ----------
    Real n-D Array with shape ``(duration * sample_rate, channel)``
    """
    func = np.sin if p['type'] == 'sine' else np.cos
    time = np.arange(0, p['duration'], 1.0 / p['sample_rate'], dtype=np.float32)
    data = p['amp'] * func(2 * np.pi * p['freq'] * time + p['phase'])
    return np.reshape(np.repeat(data, p['chan']),[len(data), p['chan']])

def generate_wav():
    if cmd.generate in ['sine', 'cosine']:
        wave_param = {
            'type': cmd.generate, 'amp': cmd.amp[0], 'freq': cmd.freq[0],
            'phase': cmd.phase[0], 'chan': cmd.channel, 'sample_rate': cmd.sample_rate,
            'duration': cmd.duration[0]
        }
        wave_data = generate_sinusoids(**wave_param)
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
    fs_ref, ref_wave = wavefile.read(cmd.reference_wave)
    if fs_wav != fs_ref:
        print('Can not compare wave with different sample rate')
        sys.exit(1)
    if cmd.analyze == 'smart_amp':
        analyze_wav_smart_amp(wave, ref_wave, fs_wav)

# remove digital zeros in two sides
def trim_wave(wave):
    # once waves go through DAC/ADC, zero will become small value close to zero,
    # here we set the digital zero threshold to 100, and cut samples below 100
    # of two sides, this has no negative impact to processing.
    ZERO_THRESHOLD_LEVEL = np.power(10, cmd.zero_threshold / 20.) * np.iinfo(wave.dtype).max
    wave_mono = wave[:,0]
    left_idx = 0
    right_idx = wave_mono.shape[0] - 1
    while True:
        if abs(wave_mono[left_idx]) > ZERO_THRESHOLD_LEVEL:
            break
        left_idx = left_idx + 1
    while True:
        if abs(wave_mono[right_idx]) > ZERO_THRESHOLD_LEVEL:
            break
        right_idx = right_idx - 1
    return wave[left_idx:right_idx,:], left_idx

# float point binary comparison is not supported, and will not be supported
# check recorded wave through smart amplifier component
def analyze_wav_smart_amp(wave, ref_wave, fs):
    trimed_ref_wave, _ = trim_wave(ref_wave)
    # compare the first two channel
    trimed_wave_ch_0_1, delay1 = trim_wave(wave[:,0:2])
    trimed_ref_wave = trimed_ref_wave[0:trimed_wave_ch_0_1.shape[0],:]
    compare_result0_1 = np.array_equal(trimed_ref_wave, trimed_wave_ch_0_1)
    # compare the second two channel
    trimed_wave_ch_2_3, delay2 = trim_wave(wave[:,2:4])
    trimed_ref_wave = trimed_ref_wave[0:trimed_wave_ch_2_3.shape[0],:]
    compare_result2_3 = np.array_equal(trimed_ref_wave, trimed_wave_ch_2_3)

    smart_amp_delay = ((delay2 - delay1) / fs * 1000)
    print('Delay of smart amplifier is %0.3fms' % smart_amp_delay)
    if compare_result0_1 and compare_result2_3 and smart_amp_delay < SMART_AMP_DELAY_THRESHOLD:
        print('Recorded wave is binary same as reference wave')
        print('Wave comparison result: PASSED')
    else:
        print('Recorded wave is not binary same as reference wave')
        print('Wave comparison result: FAILED')
        sys.exit(1001)

def parse_cmdline():
    parser = argparse.ArgumentParser(add_help=True, formatter_class=argparse.RawTextHelpFormatter,
        description='A Tool to Generate and Manipulate Wave Files.')
    parser.add_argument('-v', '--version', action='version', version='%(prog)s 1.0')
    # wave parameters
    parser.add_argument('-g', '--generate', type=str, choices=['sine','cosine'], help='generate specified types of wave')
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
    parser.add_argument('-a', '--analyze', type=str, choices=['smart_amp'], help='analyze reocrded wave to give case verdict')
    parser.add_argument('-R', '--recorded_wave', type=str, help='path of recorded wave')
    parser.add_argument('-r', '--reference_wave', type=str, help='path of reference wave')
    parser.add_argument('-Z', '--zero_threshold', type=float, default=-50.3, help='zero threshold in dBFS')
    return parser.parse_args()

def main():
    global cmd
    cmd = parse_cmdline()

    if cmd.generate is not None:
        wave_data = generate_wav()
        save_wave(wave_data)

    if cmd.analyze is not None:
        do_wave_analysis()

if __name__ == '__main__':
    main()
