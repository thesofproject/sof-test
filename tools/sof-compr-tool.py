#!/usr/bin/env python3
"""ALSA compress offload CLI tool for SOF encoder/decoder testing.

Supports capability discovery, compressed playback (decoding), and
compressed capture (encoding) directly via Linux compress offload ioctls,
including codecs and profiles not exposed by tinycompress cplay/crecord
(OPUS_RAW, ALAC, SBC/mSBC, G.722, aptX, and SND_AUDIOCODEC_BESPOKE).
"""

import argparse
import ctypes
import errno
import fcntl
import os
import re
import select
import sys
import time


# ALSA compress codec IDs from <sound/compress_params.h> and SOF extensions
SND_AUDIOCODEC_PCM = 0x01
SND_AUDIOCODEC_MP3 = 0x02
SND_AUDIOCODEC_AMR = 0x03
SND_AUDIOCODEC_AMRWB = 0x04
SND_AUDIOCODEC_AMRWBPLUS = 0x05
SND_AUDIOCODEC_AAC = 0x06
SND_AUDIOCODEC_WMA = 0x07
SND_AUDIOCODEC_REAL = 0x08
SND_AUDIOCODEC_VORBIS = 0x09
SND_AUDIOCODEC_FLAC = 0x0A
SND_AUDIOCODEC_IEC61937 = 0x0B
SND_AUDIOCODEC_G723_1 = 0x0C
SND_AUDIOCODEC_G729 = 0x0D
SND_AUDIOCODEC_BESPOKE = 0x0E
SND_AUDIOCODEC_ALAC = 0x0F
SND_AUDIOCODEC_APE = 0x10
SND_AUDIOCODEC_OPUS_RAW = 0x11
SND_AUDIOCODEC_SBC = 0x12
SND_AUDIOCODEC_G722 = 0x13
SND_AUDIOCODEC_APTX = 0x14
SND_AUDIOCODEC_APTX_HD = 0x15
SND_AUDIOCODEC_G726 = 0x16
SND_AUDIOCODEC_ALAW = 0x17
SND_AUDIOCODEC_MULAW = 0x18

AV_PROFILE_SBC_MSBC = 1

# SNDRV_PCM_FORMAT_* values used in snd_codec.format for encoders
PCM_FORMAT_MAP = {
    "NONE": 0,
    "UNDEFINED": 0,
    "S16_LE": 2,
    "S24_LE": 6,
    "S32_LE": 10,
}

CODEC_ALIASES = {
    "pcm": (SND_AUDIOCODEC_PCM, 0),
    "mp3": (SND_AUDIOCODEC_MP3, 0),
    "aac": (SND_AUDIOCODEC_AAC, 0),
    "vorbis": (SND_AUDIOCODEC_VORBIS, 0),
    "flac": (SND_AUDIOCODEC_FLAC, 0),
    "iec61937": (SND_AUDIOCODEC_IEC61937, 0),
    "bespoke": (SND_AUDIOCODEC_BESPOKE, 0),
    "alac": (SND_AUDIOCODEC_ALAC, 0),
    "ape": (SND_AUDIOCODEC_APE, 0),
    "opus": (SND_AUDIOCODEC_OPUS_RAW, 0),
    "opus_raw": (SND_AUDIOCODEC_OPUS_RAW, 0),
    "sbc": (SND_AUDIOCODEC_SBC, 0),
    "msbc": (SND_AUDIOCODEC_SBC, AV_PROFILE_SBC_MSBC),
    "g722": (SND_AUDIOCODEC_G722, 0),
    "aptx": (SND_AUDIOCODEC_APTX, 0),
    "aptx_hd": (SND_AUDIOCODEC_APTX_HD, 0),
    "g726": (SND_AUDIOCODEC_G726, 0),
    "alaw": (SND_AUDIOCODEC_ALAW, 0),
    "mulaw": (SND_AUDIOCODEC_MULAW, 0),
}

CODEC_NAMES = {
    SND_AUDIOCODEC_PCM: "PCM",
    SND_AUDIOCODEC_MP3: "MP3",
    SND_AUDIOCODEC_AMR: "AMR",
    SND_AUDIOCODEC_AMRWB: "AMRWB",
    SND_AUDIOCODEC_AMRWBPLUS: "AMRWBPLUS",
    SND_AUDIOCODEC_AAC: "AAC",
    SND_AUDIOCODEC_WMA: "WMA",
    SND_AUDIOCODEC_REAL: "REAL",
    SND_AUDIOCODEC_VORBIS: "VORBIS",
    SND_AUDIOCODEC_FLAC: "FLAC",
    SND_AUDIOCODEC_IEC61937: "IEC61937",
    SND_AUDIOCODEC_G723_1: "G723_1",
    SND_AUDIOCODEC_G729: "G729",
    SND_AUDIOCODEC_BESPOKE: "BESPOKE",
    SND_AUDIOCODEC_ALAC: "ALAC",
    SND_AUDIOCODEC_APE: "APE",
    SND_AUDIOCODEC_OPUS_RAW: "OPUS_RAW",
    SND_AUDIOCODEC_SBC: "SBC",
    SND_AUDIOCODEC_G722: "G722",
    SND_AUDIOCODEC_APTX: "APTX",
    SND_AUDIOCODEC_APTX_HD: "APTX_HD",
    SND_AUDIOCODEC_G726: "G726",
    SND_AUDIOCODEC_ALAW: "ALAW",
    SND_AUDIOCODEC_MULAW: "MULAW",
}

MAX_NUM_CODECS = 32

# Linux ioctl encoding
_IOC_NRBITS = 8
_IOC_TYPEBITS = 8
_IOC_SIZEBITS = 14
_IOC_DIRBITS = 2

_IOC_NRSHIFT = 0
_IOC_TYPESHIFT = _IOC_NRSHIFT + _IOC_NRBITS
_IOC_SIZESHIFT = _IOC_TYPESHIFT + _IOC_TYPEBITS
_IOC_DIRSHIFT = _IOC_SIZESHIFT + _IOC_SIZEBITS

_IOC_NONE = 0
_IOC_WRITE = 1
_IOC_READ = 2


def _ioc(direction, ioc_type, nr, size):
    """Build a Linux ioctl request code."""
    return (
        (direction << _IOC_DIRSHIFT)
        | (ord(ioc_type) << _IOC_TYPESHIFT)
        | (nr << _IOC_NRSHIFT)
        | (size << _IOC_SIZESHIFT)
    )


class SndEncGeneric(ctypes.Structure):
    """struct snd_enc_generic from <sound/compress_params.h>."""

    _fields_ = [
        ("bw", ctypes.c_uint32),
        ("reserved", ctypes.c_int32 * 15),
    ]


class SndDecOpusChMap(ctypes.Structure):
    """struct snd_dec_opus_ch_map from <sound/compress_params.h>."""

    _fields_ = [
        ("stream_count", ctypes.c_uint8),
        ("coupled_count", ctypes.c_uint8),
        ("channel_map", ctypes.c_uint8 * 8),
    ]


class SndDecOpus(ctypes.Structure):
    """struct snd_dec_opus from <sound/compress_params.h>."""

    _fields_ = [
        ("version", ctypes.c_uint8),
        ("num_channels", ctypes.c_uint8),
        ("pre_skip", ctypes.c_uint16),
        ("sample_rate", ctypes.c_uint32),
        ("output_gain", ctypes.c_uint16),
        ("mapping_family", ctypes.c_uint8),
        ("chan_map", SndDecOpusChMap),
    ]


class SndDecAlac(ctypes.Structure):
    """struct snd_dec_alac from <sound/compress_params.h>."""

    _fields_ = [
        ("frame_length", ctypes.c_uint32),
        ("compatible_version", ctypes.c_uint8),
        ("pb", ctypes.c_uint8),
        ("mb", ctypes.c_uint8),
        ("kb", ctypes.c_uint8),
        ("max_run", ctypes.c_uint32),
        ("max_frame_bytes", ctypes.c_uint32),
    ]


class SndDecFlac(ctypes.Structure):
    """struct snd_dec_flac from <sound/compress_params.h>."""

    _fields_ = [
        ("sample_size", ctypes.c_uint16),
        ("min_blk_size", ctypes.c_uint16),
        ("max_blk_size", ctypes.c_uint16),
        ("min_frame_size", ctypes.c_uint16),
        ("max_frame_size", ctypes.c_uint16),
        ("reserved", ctypes.c_uint16),
    ]


class SndCodecOptions(ctypes.Union):
    """union snd_codec_options from <sound/compress_params.h>."""

    _fields_ = [
        ("generic", SndEncGeneric),
        ("opus_d", SndDecOpus),
        ("alac_d", SndDecAlac),
        ("flac_d", SndDecFlac),
    ]


class SndCodec(ctypes.Structure):
    """struct snd_codec from <sound/compress_params.h>."""

    _fields_ = [
        ("id", ctypes.c_uint32),
        ("ch_in", ctypes.c_uint32),
        ("ch_out", ctypes.c_uint32),
        ("sample_rate", ctypes.c_uint32),
        ("bit_rate", ctypes.c_uint32),
        ("rate_control", ctypes.c_uint32),
        ("profile", ctypes.c_uint32),
        ("level", ctypes.c_uint32),
        ("ch_mode", ctypes.c_uint32),
        ("format", ctypes.c_uint32),
        ("align", ctypes.c_uint32),
        ("options", SndCodecOptions),
        ("pcm_format", ctypes.c_uint32),
        ("reserved", ctypes.c_uint32 * 2),
    ]


class SndComprBuffer(ctypes.Structure):
    """struct snd_compr_buffer from <sound/compress_offload.h>."""

    _fields_ = [
        ("fragment_size", ctypes.c_uint32),
        ("fragments", ctypes.c_uint32),
    ]


class SndComprParams(ctypes.Structure):
    """struct snd_compr_params from <sound/compress_offload.h>."""

    _fields_ = [
        ("buffer", SndComprBuffer),
        ("codec", SndCodec),
        ("no_wake_mode", ctypes.c_uint8),
        ("reserved", ctypes.c_uint8 * 3),
    ]


class SndComprCaps(ctypes.Structure):
    """struct snd_compr_caps from <sound/compress_offload.h>."""

    _fields_ = [
        ("num_codecs", ctypes.c_uint32),
        ("direction", ctypes.c_uint32),
        ("min_fragment_size", ctypes.c_uint32),
        ("max_fragment_size", ctypes.c_uint32),
        ("min_fragments", ctypes.c_uint32),
        ("max_fragments", ctypes.c_uint32),
        ("codecs", ctypes.c_uint32 * MAX_NUM_CODECS),
        ("reserved", ctypes.c_uint32 * 11),
    ]


class SndComprTstamp(ctypes.Structure):
    """struct snd_compr_tstamp from <sound/compress_offload.h>."""

    _fields_ = [
        ("byte_offset", ctypes.c_uint32),
        ("copied_total", ctypes.c_uint32),
        ("pcm_frames", ctypes.c_uint32),
        ("pcm_io_frames", ctypes.c_uint32),
        ("sampling_rate", ctypes.c_uint32),
    ]


assert ctypes.sizeof(SndCodec) == 120
assert ctypes.sizeof(SndComprParams) == 132
assert ctypes.sizeof(SndComprCaps) == 196
assert ctypes.sizeof(SndComprTstamp) == 20

SNDRV_COMPRESS_GET_CAPS = _ioc(
    _IOC_READ | _IOC_WRITE, "C", 0x10, ctypes.sizeof(SndComprCaps)
)
SNDRV_COMPRESS_SET_PARAMS = _ioc(
    _IOC_WRITE, "C", 0x12, ctypes.sizeof(SndComprParams)
)
SNDRV_COMPRESS_TSTAMP = _ioc(
    _IOC_READ, "C", 0x20, ctypes.sizeof(SndComprTstamp)
)
SNDRV_COMPRESS_PAUSE = _ioc(_IOC_NONE, "C", 0x30, 0)
SNDRV_COMPRESS_RESUME = _ioc(_IOC_NONE, "C", 0x31, 0)
SNDRV_COMPRESS_START = _ioc(_IOC_NONE, "C", 0x32, 0)
SNDRV_COMPRESS_STOP = _ioc(_IOC_NONE, "C", 0x33, 0)
SNDRV_COMPRESS_DRAIN = _ioc(_IOC_NONE, "C", 0x34, 0)


def resolve_device_path(device, card, dev):
    """Convert -D / hw:C,D / card+dev arguments to /dev/snd/comprCxDy."""
    if device:
        match = re.match(r"^(?:hw:|plughw:)?(\d+),(\d+)$", device)
        if match:
            return f"/dev/snd/comprC{match.group(1)}D{match.group(2)}"
        return device
    return f"/dev/snd/comprC{card}D{dev}"


def resolve_codec(codec_spec):
    """Parse codec name or hex/dec integer into (codec_id, profile)."""
    key = codec_spec.strip().lower()
    if key in CODEC_ALIASES:
        return CODEC_ALIASES[key]
    try:
        return int(key, 0), 0
    except ValueError as exc:
        raise ValueError(f"Unsupported codec specification: {codec_spec}") from exc


def resolve_pcm_format(fmt_name):
    """Parse format name or numeric value into SNDRV_PCM_FORMAT_* int."""
    key = str(fmt_name).strip().upper()
    if key in PCM_FORMAT_MAP:
        return PCM_FORMAT_MAP[key]
    try:
        return int(key, 0)
    except ValueError as exc:
        raise ValueError(f"Unsupported sample format: {fmt_name}") from exc


def query_caps(fd, direction=None):
    """Issue SNDRV_COMPRESS_GET_CAPS on an open compress fd."""
    caps = SndComprCaps()
    if direction is not None:
        caps.direction = direction
    fcntl.ioctl(fd, SNDRV_COMPRESS_GET_CAPS, caps)
    return caps


def open_compress_with_caps(dev_path, flags):
    """Open compress device and retrieve capabilities."""
    fd = os.open(dev_path, flags)
    try:
        direction = 1 if (flags & os.O_ACCMODE) == os.O_RDONLY else 0
        caps = query_caps(fd, direction=direction)
        return fd, caps
    except Exception:
        os.close(fd)
        raise


def build_params(
    caps,
    codec_id,
    profile,
    rate,
    channels,
    bitrate,
    fmt_id,
    frag_size=0,
    frags=0,
    use_bespoke=False,
    is_capture=False,
):
    """Construct SndComprParams bounded by reported caps."""
    params = SndComprParams()

    req_frag = frag_size if frag_size > 0 else (2048 if is_capture else 8192)
    req_frags = frags if frags > 0 else 4

    min_frag = caps.min_fragment_size or 1024
    max_frag = caps.max_fragment_size or 65536
    min_frags = caps.min_fragments or 2
    max_frags = caps.max_fragments or 16

    params.buffer.fragment_size = max(min_frag, min(req_frag, max_frag))
    params.buffer.fragments = max(min_frags, min(req_frags, max_frags))

    codec = params.codec
    if use_bespoke:
        codec.id = SND_AUDIOCODEC_BESPOKE
        codec.options.generic.reserved[0] = codec_id
    else:
        codec.id = codec_id

    codec.ch_in = channels
    codec.ch_out = channels
    codec.sample_rate = rate
    codec.bit_rate = bitrate
    codec.profile = profile
    codec.format = fmt_id if codec_id == SND_AUDIOCODEC_PCM else 0
    codec.pcm_format = fmt_id

    if not use_bespoke and not is_capture and codec_id == SND_AUDIOCODEC_OPUS_RAW:
        codec.options.opus_d.version = 1
        codec.options.opus_d.num_channels = channels
        codec.options.opus_d.pre_skip = 312
        codec.options.opus_d.sample_rate = 48000
        codec.options.opus_d.mapping_family = 0
        codec.options.opus_d.chan_map.stream_count = 1
        codec.options.opus_d.chan_map.coupled_count = 1 if channels >= 2 else 0
        for idx in range(min(channels, 8)):
            codec.options.opus_d.chan_map.channel_map[idx] = idx

    return params


def set_params_with_fallback(
    fd,
    caps,
    codec_id,
    profile,
    rate,
    channels,
    bitrate,
    fmt_id,
    frag_size,
    frags,
    bespoke_mode,
    is_capture,
):
    """Call SNDRV_COMPRESS_SET_PARAMS with optional BESPOKE fallback."""
    if bespoke_mode == "always":
        modes = [True]
    elif bespoke_mode == "never":
        modes = [False]
    else:
        modes = [False, True] if codec_id > SND_AUDIOCODEC_BESPOKE else [False]

    last_err = None
    for use_bespoke in modes:
        params = build_params(
            caps,
            codec_id,
            profile,
            rate,
            channels,
            bitrate,
            fmt_id,
            frag_size=frag_size,
            frags=frags,
            use_bespoke=use_bespoke,
            is_capture=is_capture,
        )
        try:
            fcntl.ioctl(fd, SNDRV_COMPRESS_SET_PARAMS, params)
            return params, use_bespoke
        except OSError as exc:
            last_err = exc
            if use_bespoke or exc.errno != errno.EINVAL:
                raise
    raise last_err


def read_tstamp(fd):
    """Best-effort query of SNDRV_COMPRESS_TSTAMP."""
    tstamp = SndComprTstamp()
    try:
        fcntl.ioctl(fd, SNDRV_COMPRESS_TSTAMP, tstamp)
    except OSError:
        return None
    return tstamp


def cmd_caps(args):
    """Inspect compress device capabilities and optionally check a codec."""
    dev_path = resolve_device_path(args.device, args.card, args.dev)
    open_flag = os.O_RDONLY if args.direction == "capture" else os.O_WRONLY
    fd, caps = open_compress_with_caps(dev_path, open_flag)
    try:
        num = min(caps.num_codecs, MAX_NUM_CODECS)
        codec_ids = [caps.codecs[i] for i in range(num)]
    finally:
        os.close(fd)

    names = [f"{CODEC_NAMES.get(cid, 'UNKNOWN')}(0x{cid:02x})" for cid in codec_ids]
    print(f"device={dev_path} direction={caps.direction} "
          f"frag=[{caps.min_fragment_size},{caps.max_fragment_size}] "
          f"frags=[{caps.min_fragments},{caps.max_fragments}] "
          f"codecs=[{', '.join(names)}]")

    if args.has_codec:
        target_id, _ = resolve_codec(args.has_codec)
        if target_id in codec_ids:
            return 0
        if SND_AUDIOCODEC_BESPOKE in codec_ids and target_id > SND_AUDIOCODEC_BESPOKE:
            print(
                f"Codec {args.has_codec} (0x{target_id:02x}) supported via BESPOKE(0x0e)",
                file=sys.stderr,
            )
            return 0
        return 2
    return 0


def cmd_play(args):
    """Play a compressed audio file through the compress playback device."""
    dev_path = resolve_device_path(args.device, args.card, args.dev)
    codec_id, default_profile = resolve_codec(args.codec)
    profile = args.profile if args.profile is not None else default_profile
    fmt_id = resolve_pcm_format(args.fmt)

    with open(args.file, "rb") as infile:
        data = infile.read()
    if not data:
        raise ValueError(f"Input file is empty: {args.file}")

    fd, caps = open_compress_with_caps(dev_path, os.O_WRONLY)
    started = False
    try:
        params, used_bespoke = set_params_with_fallback(
            fd,
            caps,
            codec_id,
            profile,
            args.rate,
            args.channels,
            args.bitrate,
            fmt_id,
            args.frag_size,
            args.frags,
            args.bespoke,
            is_capture=False,
        )
        frag_size = params.buffer.fragment_size
        prefill_bytes = min(len(data), frag_size * params.buffer.fragments)

        print(
            f"Playing {args.file} ({len(data)} B) on {dev_path} "
            f"codec=0x{codec_id:02x} profile={profile} rate={args.rate} "
            f"ch={args.channels} bespoke={used_bespoke} frag={frag_size}x{params.buffer.fragments}"
        )

        offset = 0
        started = False
        paused_done = 0
        poller = select.poll()
        poller.register(fd, select.POLLOUT)

        while offset < prefill_bytes:
            chunk = data[offset : min(offset + frag_size, prefill_bytes)]
            written = os.write(fd, chunk)
            if written <= 0:
                raise RuntimeError("Short zero-byte write during prefill")
            offset += written

        fcntl.ioctl(fd, SNDRV_COMPRESS_START)
        started = True

        while offset < len(data):
            events = poller.poll(args.timeout_ms)
            if not events:
                raise TimeoutError("Timed out waiting for POLLOUT on compress playback")
            if events[0][1] & (select.POLLERR | select.POLLHUP | select.POLLNVAL):
                raise RuntimeError(f"Compress playback poll error mask=0x{events[0][1]:x}")
            chunk = data[offset : min(offset + frag_size, len(data))]
            written = os.write(fd, chunk)
            if written <= 0:
                raise RuntimeError("Zero-byte write during compress playback")
            offset += written

            if (
                paused_done < args.pause_resume
                and offset >= len(data) // (args.pause_resume + 1) * (paused_done + 1)
            ):
                fcntl.ioctl(fd, SNDRV_COMPRESS_PAUSE)
                time.sleep(0.25)
                fcntl.ioctl(fd, SNDRV_COMPRESS_RESUME)
                paused_done += 1

        while paused_done < args.pause_resume:
            fcntl.ioctl(fd, SNDRV_COMPRESS_PAUSE)
            time.sleep(0.25)
            fcntl.ioctl(fd, SNDRV_COMPRESS_RESUME)
            paused_done += 1

        fcntl.ioctl(fd, SNDRV_COMPRESS_DRAIN)
        tstamp = read_tstamp(fd)
        if tstamp:
            print(
                f"Playback finished: bytes_written={offset} copied_total={tstamp.copied_total} "
                f"pcm_frames={tstamp.pcm_frames} rate={tstamp.sampling_rate}"
            )
        else:
            print(f"Playback finished: bytes_written={offset}")
    except Exception:
        if started:
            try:
                fcntl.ioctl(fd, SNDRV_COMPRESS_STOP)
            except OSError:
                pass
        raise
    finally:
        os.close(fd)
    return 0


def cmd_record(args):
    """Capture a compressed audio stream from the compress capture device."""
    dev_path = resolve_device_path(args.device, args.card, args.dev)
    codec_id, default_profile = resolve_codec(args.codec)
    profile = args.profile if args.profile is not None else default_profile
    fmt_id = resolve_pcm_format(args.fmt)

    fd, caps = open_compress_with_caps(dev_path, os.O_RDONLY)
    total_bytes = 0
    started = False
    try:
        params, used_bespoke = set_params_with_fallback(
            fd,
            caps,
            codec_id,
            profile,
            args.rate,
            args.channels,
            args.bitrate,
            fmt_id,
            args.frag_size,
            args.frags,
            args.bespoke,
            is_capture=True,
        )
        frag_size = params.buffer.fragment_size
        print(
            f"Recording to {args.output} from {dev_path} duration={args.duration}s "
            f"codec=0x{codec_id:02x} profile={profile} rate={args.rate} ch={args.channels} "
            f"bitrate={args.bitrate} fmt={args.fmt} bespoke={used_bespoke} "
            f"frag={frag_size}x{params.buffer.fragments}"
        )

        poller = select.poll()
        poller.register(fd, select.POLLIN)

        with open(args.output, "wb") as outfile:
            fcntl.ioctl(fd, SNDRV_COMPRESS_START)
            started = True
            deadline = time.monotonic() + args.duration

            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                if args.max_bytes and total_bytes >= args.max_bytes:
                    break
                wait_ms = max(1, min(int(remaining * 1000), 500))
                events = poller.poll(wait_ms)
                if not events:
                    continue
                if events[0][1] & (select.POLLERR | select.POLLNVAL):
                    raise RuntimeError(
                        f"Compress capture poll error mask=0x{events[0][1]:x}"
                    )
                if events[0][1] & select.POLLIN:
                    chunk = os.read(fd, frag_size)
                    if not chunk:
                        break
                    outfile.write(chunk)
                    total_bytes += len(chunk)

        if started:
            fcntl.ioctl(fd, SNDRV_COMPRESS_STOP)
            started = False

        tstamp = read_tstamp(fd)
        if tstamp:
            print(
                f"Capture finished: bytes_captured={total_bytes} "
                f"copied_total={tstamp.copied_total} pcm_frames={tstamp.pcm_frames}"
            )
        else:
            print(f"Capture finished: bytes_captured={total_bytes}")
    finally:
        if started:
            try:
                fcntl.ioctl(fd, SNDRV_COMPRESS_STOP)
            except OSError:
                pass
        os.close(fd)

    if total_bytes <= 0:
        raise RuntimeError("Captured 0 bytes from compress device")
    return 0


def parse_args():
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(
        description="ALSA compress offload test tool for SOF"
    )
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    def add_dev_args(sub):
        sub.add_argument("-D", "--device", help="Device path (/dev/snd/comprC0D2 or hw:0,2)")
        sub.add_argument("-c", "--card", type=int, default=0, help="ALSA card index")
        sub.add_argument("-d", "--dev", type=int, default=0, help="Compress device index")

    p_caps = subparsers.add_parser("caps", help="Query compress device capabilities")
    add_dev_args(p_caps)
    p_caps.add_argument(
        "--direction",
        choices=("playback", "capture"),
        default="playback",
        help="Open mode / stream direction",
    )
    p_caps.add_argument(
        "--has-codec",
        help="Exit 0 if codec is supported, 2 otherwise",
    )
    p_caps.set_defaults(func=cmd_caps)

    p_play = subparsers.add_parser("play", help="Play compressed audio file")
    add_dev_args(p_play)
    p_play.add_argument("-C", "--codec", required=True, help="Codec name or hex id")
    p_play.add_argument("-f", "--file", required=True, help="Compressed input file")
    p_play.add_argument("-r", "--rate", type=int, default=48000, help="Sample rate")
    p_play.add_argument("-n", "--channels", type=int, default=2, help="Channel count")
    p_play.add_argument("-b", "--bitrate", type=int, default=128000, help="Bitrate (bps)")
    p_play.add_argument("--profile", type=int, default=None, help="Codec profile")
    p_play.add_argument("--fmt", default="UNDEFINED", help="Codec format field")
    p_play.add_argument("--frag-size", type=int, default=0, help="Buffer fragment size")
    p_play.add_argument("--frags", type=int, default=0, help="Buffer fragment count")
    p_play.add_argument(
        "--bespoke",
        choices=("auto", "always", "never"),
        default="auto",
        help="BESPOKE codec wrapper behavior",
    )
    p_play.add_argument(
        "--pause-resume",
        type=int,
        default=0,
        help="Number of PAUSE/RESUME cycles during playback",
    )
    p_play.add_argument(
        "--timeout-ms",
        type=int,
        default=10000,
        help="POLLOUT timeout in milliseconds",
    )
    p_play.set_defaults(func=cmd_play)

    p_rec = subparsers.add_parser("record", help="Record compressed audio stream")
    add_dev_args(p_rec)
    p_rec.add_argument("-C", "--codec", required=True, help="Codec name or hex id")
    p_rec.add_argument("-o", "--output", required=True, help="Output compressed file")
    p_rec.add_argument("-t", "--duration", type=float, default=3.0, help="Duration (s)")
    p_rec.add_argument("-r", "--rate", type=int, default=48000, help="Sample rate")
    p_rec.add_argument("-n", "--channels", type=int, default=2, help="Channel count")
    p_rec.add_argument("-b", "--bitrate", type=int, default=128000, help="Bitrate (bps)")
    p_rec.add_argument("--profile", type=int, default=None, help="Codec profile")
    p_rec.add_argument("--fmt", default="UNDEFINED", help="Stream/PCM format (UNDEFINED/S16_LE/S32_LE)")
    p_rec.add_argument("--frag-size", type=int, default=0, help="Buffer fragment size")
    p_rec.add_argument("--frags", type=int, default=0, help="Buffer fragment count")
    p_rec.add_argument("--max-bytes", type=int, default=0, help="Stop after N bytes")
    p_rec.add_argument(
        "--bespoke",
        choices=("auto", "always", "never"),
        default="auto",
        help="BESPOKE codec wrapper behavior",
    )
    p_rec.set_defaults(func=cmd_record)

    return parser.parse_args()


def main():
    """CLI entrypoint."""
    args = parse_args()
    try:
        return args.func(args)
    except Exception as exc:  # pylint: disable=broad-except
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
