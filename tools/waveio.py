#!/usr/bin/env python3

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2021 Intel Corporation. All rights reserved.

"""
The WaveIO library is used to read and write standard PCM wave file.
"""

import struct
import wave
import numpy as np

def _normalize(data, bits):
    signed_max = _get_signed_max_by_bits(bits)
    # normalize data with negative max here to avoid the
    # normalized negative max < -1.0
    return data / (signed_max + 1)

def _get_signed_max_by_bits(bits):
    return 2 ** (bits - 1) - 1

def _quantize(data, bits):
    np_dtype = np.int16 if bits == 16 else np.int32
    # The np.astype() behaves like fix() in Matlab, it rounds each element
    # in a ndarray to the nearest integer towards zero, eg:
    # -2.8 -> -2, -2.1 -> -2, 2.1 -> 2, 2.8 -> 2,
    # so add +0.5 to the positive part and -0.5 to the negative part to make
    # the arithmetic bahaves like round() in Matlab to ensure correct quantization.
    data = data * _get_signed_max_by_bits(bits) + 0.5 * np.sign(data)
    return data.astype(np_dtype)

# reshape linear data to matrix with shape = frames * channels
def _reshape_audio_data(data, channels):
    if channels == 1:
        return data
    frames = data.shape[0] // channels
    reshaped_data = np.zeros((frames, channels))
    for i in range(channels):
        reshaped_data[:, i] = data[i::channels]
    return reshaped_data

# Wave header: http://soundfile.sapp.org/doc/WaveFormat/
def _read_wave_file(filepath):
    with open(filepath, 'rb') as wfs:
        raw_data = wfs.read()

    (audio_format,) = struct.unpack('H', raw_data[20:22])
    if audio_format != 1:
        raise Exception("Unknown wave file format, only standard PCM is supported")

    (channels,) = struct.unpack('H', raw_data[22:24])
    (sample_rate,) = struct.unpack('I', raw_data[24:28])
    (block_align,) = struct.unpack('H', raw_data[32:34])
    (sample_bits,) = struct.unpack('H', raw_data[34:36])
    (data_size,) = struct.unpack('I', raw_data[40:44])
    fmt_dict = {(16, 2):'S16_LE', (24, 3):'S24_3LE', (24, 4):'S24_LE', (32, 4):'S32_LE'}
    wave_format = fmt_dict[(sample_bits, block_align//channels)]
    # raw data starts from 44th byte
    wave_data = raw_data[44: 44 + data_size]
    return wave_data, channels, sample_rate, wave_format, sample_bits

def read_wave(filepath='tmp.wav'):
    """
    Read wave data from standard PCM wave file to numpy ndarray

    Parameters
    ----------
    filepath: Path of standard PCM wave file

    Returns
    ----------
    wave_data: tuple contains two elements, normalized data and sample rate
    """

    wave_data_bin, channels, sample_rate, fmt, sample_bits = _read_wave_file(filepath)

    # S24_3LE, append 0x00 to least significant byte
    if fmt == 'S24_3LE':
        frames = len(wave_data_bin) // 3
        raw_data_arr = [b'\00' + wave_data_bin[3 * i: 3*i + 3] for i in range(frames)]
        raw_data_s32 = b''.join(raw_data_arr)
        data = np.frombuffer(raw_data_s32, dtype=np.int32) / 256.0
    # S16_LE, S24_LE and S32_LE
    else:
        np_dtype = np.int16 if sample_bits == 16 else np.int32
        data = np.frombuffer(wave_data_bin, dtype=np_dtype)

    reshaped_data = _reshape_audio_data(data, channels)
    normalized_data = _normalize(reshaped_data, sample_bits)
    return normalized_data, sample_rate

def write_wave(filepath, wave_data, sample_rate, fmt):
    """
    Write wave data to file

    Parameters
    ----------
    filepath: Path of wave file to be written to
    wave_data: The data to write to file
    sample_rate: Audio sample rate
    fmt: Wave file format, supported formats are: S16_LE, S24_3LE, S24_LE and S32_LE
    """

    channels = 1 if len(wave_data.shape) == 1 else wave_data.shape[1]
    frames = wave_data.shape[0]
    inv_fmt_dict = {'S16_LE':(16, 2), 'S24_3LE': (24, 3), 'S24_LE':(24, 4), 'S32_LE':(32, 4)}
    sample_bits, block_align = inv_fmt_dict[fmt]
    wave_data = _quantize(wave_data, sample_bits)
    wave_data_bin = wave_data.tobytes()

    if fmt == 'S24_3LE': # remove least significant byte
        wave_data_bin_arr = [wave_data_bin[4 * i: 4 * i + 3] for i in range(frames * 2)]
        wave_data_bin = b''.join(wave_data_bin_arr)

    with wave.open(filepath, 'wb') as wfs:
        wave_params = (channels, block_align, sample_rate, frames, 'NONE', 'NONE')
        # pylint identifies wfs as a Wave_read object, but it is a Wave_write object
        # pylint: disable=E1101
        wfs.setparams(wave_params)
        wfs.writeframes(wave_data_bin)

    if fmt == 'S24_LE': # for S24_LE, we need to update sample_bits from 32 to 24
        with open(filepath, 'rb+') as wfs:
            sample_bits_bin = np.array([sample_bits]).astype(np.int16).tobytes()
            raw_wave = bytearray(wfs.read())
            raw_wave[34:36] = sample_bits_bin
            wfs.seek(0, 0) # seek to the beginning of the file
            wfs.write(raw_wave)

if __name__ == '__main__':
    import argparse

    def main():
        """
        Entrance of the light-weight format converter
        """

        command_line = parse_command_line()
        wave_data, sample_rate = read_wave(command_line.filename)
        write_wave(command_line.output, wave_data, sample_rate, command_line.convert_to)

    def parse_command_line():
        """
        This function is used to parse command line parameters
        """

        supported_format = ['S16_LE', 'S24_3LE', 'S24_LE', 'S32_LE']
        parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter,
            description='A Light-Weight Wave Format Converter')
        argparse.ArgumentParser()
        parser.add_argument('filename', type=str, help='Path of input wave file')
        parser.add_argument('-t', '--convert_to', type=str, choices=supported_format,
            help="Target wave file format")
        parser.add_argument('-o', '--output', type=str, help="Path of output wave file")
        return parser.parse_args()

    main()
