#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2024 Google LLC
# Author: Andy Ross <andyross@google.com>
import os
import re
import sys
import time
import struct
import random
import argparse
import ctypes as C

HELP_TEXT="""
Simple dependency-free ALSA test rig for PCM capture analysis.

Just drop this script on a test device to run it.  No tools to build,
no dependencies to install.  Confirmed to run on Python 3.8+ with
nothing more than the core libraries and a working libasound.so.2
visible to the runtime linker.

When run without arguments, the tool will record from the capture
device for the specified duration, then emit the resulting samples
back out the playback device without processing (except potentially to
convert the sample format from s32_le to s16_le if needed, and to
discard any channels beyond those supported by the playback device).

Passing --chirp-test enables a playback-to-capture latency detector:
the tool will emit a short ~6 kHz wave packet via ALSA's mmap
interface (which allows measuring and correcting for the buffer
latency from the userspace process) and simultaneously loop on short
reads from the capture device looking for the moment it arrives.

Passing --echo-test enables a capture-while-playback test.  The script
will play a specified .wav file ("noise.wav" by default) for the
specified duration, while simultaneously capturing, and report the
"power" (in essentially arbitrary units, but it's linear with actual
signal energy assuming the sample space is itself linear) of the
captured data to stdout at the end of the test.

The tool supports a "--disable-rtnr" for the specific case of RTNR
noise reduction, which has been observed to suppress the chirp test
occasionally.  It does not otherwise change the runtime configuration
of the ALSA device and expects it to be configured by the user for the
specific case under test.
"""

def parse_opts():
    global opts
    ap = argparse.ArgumentParser(description=HELP_TEXT,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--disable-rtnr", action="store_true", help="Disable RTNR noise reduction")
    ap.add_argument("-c", "--card", type=int, default=0, help="ALSA card index")
    ap.add_argument("--pcm", type=int, default=16, help="Output ALSA PCM index")
    ap.add_argument("--cap", type=int, default=18, help="Capture ALSA PCM index")
    ap.add_argument("--rate", type=int, default=48000, help="Sample rate")
    ap.add_argument("--chan", type=int, default=2, help="Output channel count")
    ap.add_argument("--capchan", type=int,
                      help="Capture channel count (if different from output)")
    ap.add_argument("--capbits", type=int, default=16, help="Capture sample bits (16 or 32)")
    ap.add_argument("--noise", default="noise.wav",
                      help="WAV file containing 'noise' for capture")
    ap.add_argument("--duration", type=int, default=3, help="Capture duration (seconds)")
    ap.add_argument("--chirpcyc", type=int, default=120, help="Repetitions of chirp waveform")
    ap.add_argument("--chirp-test", action="store_true",
                      help="Test latency with synthesized audio")
    ap.add_argument("--echo-test", action="store_true", help="Test simultaneous capture/playback")

    opts = ap.parse_args()
    if not opts.capchan:
        opts.capchan = opts.chan
    opts.base_test = not (opts.chirp_test or opts.echo_test)

class ALSA:
    """
    Tiny ctypes stub.  Wraps the alsa API such that errno returns (at
    least ones that look like an errno) become OSErrors and don't need
    to be checked.  Includes a generalized alloc() that wraps all the
    _sizeof() predicates and allocates from the (safe/collected) python
    heap.  Provides a simple spot for putting (manually-derived)
    constants.  The ALSA C API is mostly-structless and quite simple, so
    this tends to work well without a lot of ctypes use except for an
    occasional constructed integer or byref() pointer.
    """
    PCM_STREAM_PLAYBACK = 0
    PCM_STREAM_CAPTURE = 1
    PCM_FORMAT_S16_LE = 2
    PCM_FORMAT_S32_LE = 10
    PCM_ACCESS_MMAP_INTERLEAVED = 0
    PCM_ACCESS_RW_INTERLEAVED = 3
    def __init__(self):
        self.lib = C.cdll.LoadLibrary("libasound.so.2")
    def __getattr__(self, name):
        fn = getattr(self.lib, name)
        if name.endswith("_name"): # These return strings!
            fn.restype = C.c_char_p
            return lambda *args: fn(*args).decode("utf-8")
        return lambda *args: ALSA.err_wrap(fn(*args))
    @staticmethod
    def err_wrap(ret):
        if -200 < ret < 0:
            raise OSError(os.strerror(-ret))
        return ret
    def alloc(self, typ):
        return (C.c_byte * getattr(self.lib, f"snd_{typ}_sizeof")())()
    class pcm_channel_area_t(C.Structure):
        _fields_ = [("addr", C.c_ulong), ("first", C.c_int), ("step", C.c_int)]

def pcm_init_stream(pcm, rate, chans, fmt, access):
    hwp = alsa.alloc("pcm_hw_params")
    alsa.snd_pcm_hw_params_any(pcm, hwp)
    alsa.snd_pcm_hw_params_set_format(pcm, hwp, fmt)
    alsa.snd_pcm_hw_params_set_channels(pcm, hwp, chans)
    alsa.snd_pcm_hw_params_set_rate(pcm, hwp, rate, alsa.PCM_STREAM_PLAYBACK)
    alsa.snd_pcm_hw_params_set_access(pcm, hwp, access)
    alsa.snd_pcm_hw_params(pcm, hwp)

def ctl_disable_rtnr():
    """
    Noise reduction likes to squash our chirp on capture.  Walk the list
    of controls, looking for an RTNR enable control, if one exists, and
    set it to false.  Unbelievably cumbersome API to do this: call
    elem_list once on an empty struct to get the element count, then
    allocate, then call it again.  Then for each element we can check
    the name directly, but need to allocate an "id" struct to query an
    abstract identifier, that we use with a separately-allocated "value"
    (on which we set the dyncmically typed data) to send the command to
    the kernel.
    """
    dev = f"hw:{opts.card}".encode("ascii")
    ctl = C.c_ulong()
    alsa.snd_ctl_open(C.byref(ctl), dev, 0)
    elist = alsa.alloc("ctl_elem_list")
    alsa.snd_ctl_elem_list(ctl, elist)
    nelem = alsa.snd_ctl_elem_list_get_count(elist)
    alsa.snd_ctl_elem_list_alloc_space(elist, nelem)
    alsa.snd_ctl_elem_list(ctl, elist)
    for i in range(nelem):
        name = alsa.snd_ctl_elem_list_get_name(elist, i)
        if re.match(r'RTNR.*\s+rtnr_enable.*', name):
            print(f"Disabling control: {name}")
            eid = alsa.alloc("ctl_elem_id")
            val = alsa.alloc("ctl_elem_value")
            alsa.snd_ctl_elem_list_get_id(elist, i, C.byref(eid))
            alsa.snd_ctl_elem_value_set_id(val, eid)
            alsa.snd_ctl_elem_value_set_boolean(val, 0, False)
            alsa.snd_ctl_elem_write(ctl, val)
    alsa.snd_ctl_close(ctl)

def pcm_play_buf(data):
    data = bytearray(data)
    addr = C.addressof((C.c_byte * 1).from_buffer(data))
    off = 0
    n = int(len(data) / (2 * opts.chan))
    n = min(n, opts.rate * opts.duration)

    pcm = C.c_long(0)
    dev = f"hw:{opts.card},{opts.pcm}".encode("ascii")
    alsa.snd_pcm_open(C.byref(pcm), dev, alsa.PCM_STREAM_PLAYBACK, 0)
    pcm_init_stream(pcm, opts.rate, opts.chan, alsa.PCM_FORMAT_S16_LE,
                    alsa.PCM_ACCESS_RW_INTERLEAVED)
    while n > 0:
        f = alsa.snd_pcm_writei(pcm, C.c_ulong(addr + off), n)
        n -= f
        off += f
    alsa.snd_pcm_drain(pcm)
    alsa.snd_pcm_close(pcm)

def pcm_play_chirp():
    pcm = C.c_long(0)
    dev = f"hw:{opts.card},{opts.pcm}".encode("ascii")
    alsa.snd_pcm_open(C.byref(pcm), dev, alsa.PCM_STREAM_PLAYBACK, 0)
    pcm_init_stream(pcm, opts.rate, opts.chan, alsa.PCM_FORMAT_S16_LE,
                    alsa.PCM_ACCESS_MMAP_INTERLEAVED)

    (chirp, chirp_frames) = gen_chirp_s16le()

    # Reset the stream and queue up as much data as will fit in the
    # ring buffer
    area = alsa.pcm_channel_area_t()
    offset = C.c_ulong()
    frames = C.c_ulong(opts.rate)
    ring_frames = 0
    alsa.snd_pcm_prepare(pcm)
    alsa.snd_pcm_reset(pcm)
    while True:
        alsa.snd_pcm_avail_update(pcm)
        alsa.snd_pcm_mmap_begin(pcm, C.byref(area), C.byref(offset), C.byref(frames))
        committed = alsa.snd_pcm_mmap_commit(pcm, offset, frames)
        ring_frames += committed
        if committed == 0:
            break

    silence = bytes(2 * opts.chan * ring_frames)

    # Start up the stream, spin until there is space in the buffer,
    # write the chirp.  This minimizes client-side overhead like
    # stream startup.  Then immediately take a timestamp and write
    # silence for one full cycle (to be 100% sure the buffer can't
    # wrap and chirp twice).
    alsa.snd_pcm_start(pcm)
    while alsa.snd_pcm_avail(pcm) < chirp_frames:
        pass
    pre_buffered = ring_frames - alsa.snd_pcm_avail(pcm)
    f = alsa.snd_pcm_mmap_writei(pcm, chirp, chirp_frames)
    chirp_sent = time.perf_counter()
    assert f == chirp_frames

    n = 0
    while n < ring_frames:
        n += alsa.snd_pcm_mmap_writei(pcm, silence, ring_frames)
    alsa.snd_pcm_drain(pcm)
    alsa.snd_pcm_close(pcm)

    # Correct chirp_sent for buffered data!
    chirp_sent += pre_buffered / opts.rate
    return chirp_sent

def pcm_do_capture(duration):
    """
    Returns an array of tuples of (timestamp, bytes), no processing done
    here for performance reasons, just one heap allocation and copy.
    """
    pcm = C.c_long(0)
    fmt = alsa.PCM_FORMAT_S32_LE if opts.capbits == 32 else alsa.PCM_FORMAT_S16_LE
    capsz = 4 if opts.capbits == 32 else 2
    dev = f"hw:{opts.card},{opts.cap}".encode("ascii")
    alsa.snd_pcm_open(C.byref(pcm), dev, alsa.PCM_STREAM_CAPTURE, 0)
    pcm_init_stream(pcm, opts.rate, opts.capchan, fmt, alsa.PCM_ACCESS_RW_INTERLEAVED)
    frames_remaining = duration * opts.rate
    buf_frames = int(opts.rate / 1000) # 1ms blocks
    fsz = opts.capchan * capsz
    buf = bytearray(fsz * buf_frames)
    addr = C.c_ulong(C.addressof((C.c_byte * 1).from_buffer(buf)))
    buflist = []
    buf_frames = C.c_ulong(buf_frames)
    while frames_remaining > 0:
        f = alsa.snd_pcm_readi(pcm, addr, buf_frames)
        t = time.perf_counter()
        frames_remaining -= f
        buflist.append((t, bytes(buf[0:f * fsz])))
    return buflist

def gen_chirp_s16le():
    """
    A programmatically-detectable chirp/pop signal for testing latency.
    To minimize latency, we want the chirp to be low duration, high
    energy and high frequency.  This repeats an 8-sample square wave (6
    kHz at 48k sample rate).  Some devices can reproduce this well with
    as few as 8 repetitions (1.3ms), but on at least one mt8195 device
    it's unreliably audible unless repeated 128 times!  It's not caused
    by software in the DSP, more like a codec/amp feature (possibly
    related to power management, if we don't play other audio
    immediately before, it's even less reliable).
    """
    reps = 4
    chirp = b''
    for _ in range(opts.chirpcyc):
        n = opts.chan * reps
        vals = [-0x8000] * n + [0x7fff] * n
        chirp += struct.pack(f"{2*n}h", *vals)
    return (chirp, opts.chirpcyc * reps)

def cap_to_playback(buf):
    """
    Converts a byte array containing capture frames (which can have
    different sample format and channel count) to the playback format
    (always s16_le).  Also computes an "energy" value as the sum of
    absolute sample differences (in units of +/-1.0) over all result
    channels.  Returns both as a tuple.
    """
    capfmt = ('i' if opts.capbits == 32 else 'h') * opts.capchan
    capsz = opts.capchan * (4 if opts.capbits == 32 else 2)
    scale = 1 / (1 << (opts.capbits - 1))
    last_frame = []
    delta_sum = 0
    out_frames = []

    # NOTE: should consider low-passing the energy computation by
    # averaging ~N recent samples.  Otherwise high frequency noise can
    # dominate, which we don't really care about measuring (AEC can't
    # treat it, and it can plausibly create false positive chirp signals
    # loud enough).
    for i in range(0, len(buf), capsz):
        frame = [scale * x for x in struct.unpack(capfmt, buf[i:i+capsz])[0:opts.chan]]
        if last_frame:
            delta_sum += sum(abs(last_frame[x] - frame[x]) for x in range(opts.chan))
        last_frame = frame
        iframe = [int(min(0x7fff, max(-0x8000, (1 << 15) * e))) for e in frame]
        out_frames.append(struct.pack(f'{opts.chan}h', *iframe))
    return (b''.join(out_frames), delta_sum)

def chirp_child(wpipe):
    for rec in pcm_do_capture(opts.duration):
        t = rec[0]
        (buf, energy) = cap_to_playback(rec[1])
        frames = len(buf) / (2 * opts.chan)

        # Normalize energy as "half-swing per sample" and check vs. a
        # threshold that will trigger if we get a 0.1 unit swing over
        # the 8-sample chirp waveform.
        #
        # NOTE: would be possible to do this analysis at the
        # individual sample layer for better time fidelity instead of
        # in 1ms chunks.
        energy = energy / (frames * opts.chan)
        if energy > (0.1/8):
            os.write(wpipe, f"{t}".encode("ascii"))
            return

def echo_child(wpipe):
    energy = 0
    for rec in pcm_do_capture(opts.duration):
        energy += cap_to_playback(rec[1])[1]

    # Normalize energy to "half-swing per second" here, just to make
    # essentially arbitrary numbers prettier (e.g. a typical pop music
    # track results in ~few-hundred values for "energy")
    energy /= (opts.duration * opts.chan)
    os.write(wpipe, f"{energy:.3f}".encode("ascii"))

def chirp_test():
    """
    Forks a child process to listen for the chirp and write back a
    time.perf_counter() value (which is an invariant clock across
    processes) through a pipe.
    """
    (rfd, wfd) = os.pipe()
    pid = os.fork()
    if pid == 0:
        chirp_child(wfd)
        sys.exit(0)

    # Randomly sleep for a bit to make aliasing bugs (e.g. noise being
    # detected as a chirp) visible as unreliable output.
    time.sleep(random.randint(1000, 2000)/1000)
    chirp_sent = pcm_play_chirp()

    os.waitpid(pid, 0)
    msg = os.read(rfd, 9999).decode("ascii")
    chirp_detected = float(msg)

    lat_ms = (chirp_detected - chirp_sent) * 1000
    print(f"Chirp latency: {lat_ms:.1f} ms")

def echo_test():
    """
    Similar to chirp test, but plays a .wav file while the child
    captures, and reports average capture energy (useful for testing mic
    gain and echo cancellation performance)
    """
    # Just slurps in the wav file and chops off the header, assuming
    # the user got the format and sampling rate correct.
    WAV_HDR_LEN = 44
    buf = open(opts.noise, "rb").read()[WAV_HDR_LEN:]

    (rfd, wfd) = os.pipe()
    pid = os.fork()
    if pid == 0:
        echo_child(wfd)
        sys.exit(0)

    pcm_play_buf(buf)

    os.waitpid(pid, 0)
    msg = os.read(rfd, 9999).decode("ascii")
    print("Capture energy:", msg)

def base_test():
    """
    Simplest test: Just capture opts.duration seconds worth of data,
    convert to playback format, and play it.
    """
    bufs = []
    energy = 0
    for rec in pcm_do_capture(opts.duration):
        crec = cap_to_playback(rec[1])
        bufs.append(crec[0])
        energy += crec[1]
    pcm_play_buf(b''.join(bufs))
    print(f"Energy {energy}")

def main():
    parse_opts()
    if opts.disable_rtnr:
        ctl_disable_rtnr()
    if opts.base_test:
        base_test()
    if opts.chirp_test:
        chirp_test()
    if opts.echo_test:
        echo_test()

opts = None
alsa = ALSA()
if __name__ == "__main__":
    main()
