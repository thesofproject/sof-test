#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause

"""Stimulus generator and DSP verification analyzer for WebRTC sof-test cases."""

import argparse
import array
import math
import os
import random
import struct
import sys
import wave

try:
    import numpy as np
except ImportError:
    np = None

SYNC_PRE_SEC = 0.15
SYNC_CHIRP_SEC = 0.30
SYNC_POST_SEC = 0.25
SYNC_HEADER_SEC = SYNC_PRE_SEC + SYNC_CHIRP_SEC + SYNC_POST_SEC
CHIRP_F0_HZ = 450.0
CHIRP_F1_HZ = 2800.0
PRNG_SEED = 42


def db_to_amp(db_val):
    """Convert dBFS value to linear peak amplitude in [0, 1]."""
    return 10.0 ** (db_val / 20.0)


def rms_db(samples):
    """Compute RMS level in dBFS for normalized floats in [-1.0, 1.0]."""
    if len(samples) == 0:
        return -120.0
    if np is not None:
        arr = np.asarray(samples, dtype=np.float64)
        mean_sq = float(np.mean(arr * arr))
    else:
        mean_sq = sum(x * x for x in samples) / len(samples)
    if mean_sq <= 1e-12:
        return -120.0
    return 10.0 * math.log10(mean_sq)


def peak_db(samples):
    """Compute peak magnitude in dBFS for normalized floats in [-1.0, 1.0]."""
    if len(samples) == 0:
        return -120.0
    if np is not None:
        peak = float(np.max(np.abs(samples)))
    else:
        peak = max(abs(x) for x in samples)
    if peak <= 1e-9:
        return -120.0
    return 20.0 * math.log10(peak)


def _goertzel_mag_sq_numpy(samples, rate, freq_hz):
    """Compute single-bin Goertzel squared magnitude using numpy."""
    arr = np.asarray(samples, dtype=np.float64)
    ang = 2.0 * math.pi * freq_hz / rate
    idx = np.arange(len(arr), dtype=np.float64)
    c_sum = float(np.dot(arr, np.cos(ang * idx)))
    s_sum = float(np.dot(arr, np.sin(ang * idx)))
    return 2.0 * (c_sum * c_sum + s_sum * s_sum) / (len(arr) * len(arr))


def _goertzel_mag_sq_py(samples, rate, freq_hz):
    """Compute single-bin Goertzel squared magnitude using pure Python."""
    coeff = 2.0 * math.cos(2.0 * math.pi * freq_hz / rate)
    q1 = 0.0
    q2 = 0.0
    for x in samples:
        q0 = coeff * q1 - q2 + x
        q2 = q1
        q1 = q0
    power = q1 * q1 + q2 * q2 - coeff * q1 * q2
    return 2.0 * max(power, 0.0) / (len(samples) * len(samples))


def goertzel_power_db(samples, rate, freq_hz):
    """Measure single-frequency RMS tone level in dBFS via Goertzel filter."""
    if len(samples) == 0:
        return -120.0
    if np is not None:
        mag_sq = _goertzel_mag_sq_numpy(samples, rate, freq_hz)
    else:
        mag_sq = _goertzel_mag_sq_py(samples, rate, freq_hz)
    if mag_sq <= 1e-12:
        return -120.0
    return 10.0 * math.log10(mag_sq)


def make_chirp(rate):
    """Generate deterministic log sync chirp normalized to [-1.0, 1.0]."""
    n_chirp = int(round(SYNC_CHIRP_SEC * rate))
    amp = db_to_amp(-8.0)
    k = math.log(CHIRP_F1_HZ / CHIRP_F0_HZ) / SYNC_CHIRP_SEC
    out = [0.0] * n_chirp
    fade = max(1, int(0.01 * rate))
    for i in range(n_chirp):
        t = i / rate
        phase = 2.0 * math.pi * CHIRP_F0_HZ * (math.exp(k * t) - 1.0) / k
        env = 1.0
        if i < fade:
            env = i / fade
        elif i >= n_chirp - fade:
            env = (n_chirp - 1 - i) / fade
        out[i] = amp * env * math.sin(phase)
    return out


def make_sine(rate, dur_sec, freq_hz, level_dbfs):
    """Generate sine wave normalized to [-1.0, 1.0]."""
    n = int(round(dur_sec * rate))
    amp = db_to_amp(level_dbfs)
    omega = 2.0 * math.pi * freq_hz / rate
    return [amp * math.sin(omega * i) for i in range(n)]


def make_multitone(rate, dur_sec, freqs_hz, level_dbfs):
    """Generate equal-amplitude harmonic-free speech-proxy multitone."""
    n = int(round(dur_sec * rate))
    per_tone = db_to_amp(level_dbfs) / math.sqrt(len(freqs_hz))
    omegas = [2.0 * math.pi * f / rate for f in freqs_hz]
    phases = [0.7 * idx for idx in range(len(freqs_hz))]
    return [
        per_tone * sum(math.sin(w * i + ph) for w, ph in zip(omegas, phases))
        for i in range(n)
    ]


def make_noise(rate, dur_sec, rms_dbfs, rng):
    """Generate deterministic stationary broadband noise at target RMS dBFS."""
    n = int(round(dur_sec * rate))
    raw = [rng.gauss(0.0, 1.0) for _ in range(n)]
    cur_rms = math.sqrt(sum(x * x for x in raw) / max(n, 1))
    scale = db_to_amp(rms_dbfs) / max(cur_rms, 1e-9)
    return [max(-0.99, min(0.99, x * scale)) for x in raw]


def _encode_pcm_frames(mono_samples, channels, sampwidth):
    """Pack normalized [-1, 1] mono floats into interleaved PCM bytes."""
    max_pos = 2147483647 if sampwidth == 4 else 32767
    min_neg = -2147483648 if sampwidth == 4 else -32768

    if np is not None:
        dtype = np.int32 if sampwidth == 4 else np.int16
        arr = np.clip(np.asarray(mono_samples, dtype=np.float64), -1.0, 1.0)
        ints = np.clip(np.rint(arr * max_pos), min_neg, max_pos).astype(dtype)
        if channels > 1:
            ints = np.repeat(ints[:, None], channels, axis=1)
        return ints.tobytes()

    packed = bytearray()
    pack_fmt = "<i" if sampwidth == 4 else "<h"
    for val in mono_samples:
        clamped = max(-1.0, min(1.0, val))
        ival = max(min_neg, min(max_pos, int(round(clamped * max_pos))))
        frame = struct.pack(pack_fmt, ival)
        packed.extend(frame * channels)
    return bytes(packed)


def write_wav(path, mono_samples, rate, channels, fmt):
    """Write normalized [-1, 1] mono signal replicated across channels to WAV."""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    sampwidth = 4 if fmt == "S32_LE" else 2
    payload = _encode_pcm_frames(mono_samples, channels, sampwidth)

    with wave.Wave_write(path) as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(sampwidth)
        wf.setframerate(rate)
        wf.writeframes(payload)


def read_wav(path):
    """Read WAV file and return (channel_0_floats, rate, channels, sampwidth)."""
    with wave.Wave_read(path) as wf:
        channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        rate = wf.getframerate()
        raw = wf.readframes(wf.getnframes())

    if sampwidth == 2:
        typecode = "h"
        scale = 1.0 / 32768.0
    elif sampwidth == 4:
        typecode = "i"
        scale = 1.0 / 2147483648.0
    else:
        raise ValueError(f"Unsupported WAV sample width {sampwidth} in {path}")

    if np is not None:
        dtype = np.int16 if sampwidth == 2 else np.int32
        arr = np.frombuffer(raw, dtype=dtype).reshape(-1, channels)
        return (arr[:, 0].astype(np.float64) * scale).tolist(), rate, channels, sampwidth

    pcm = array.array(typecode)
    pcm.frombytes(raw)
    ch0 = [pcm[i] * scale for i in range(0, len(pcm), channels)]
    return ch0, rate, channels, sampwidth


def build_sync_header(rate):
    """Build [pre_silence | chirp | post_silence] sync header."""
    pre = [0.0] * int(round(SYNC_PRE_SEC * rate))
    chirp = make_chirp(rate)
    post = [0.0] * int(round(SYNC_POST_SEC * rate))
    return pre + chirp + post


def mix_signals(sig_a, sig_b):
    """Element-wise sum clamped to [-0.999, 0.999]."""
    return [max(-0.999, min(0.999, a + b)) for a, b in zip(sig_a, sig_b)]


def _generate_aec_pair(args, rng, header):
    """Generate synchronized mic (echo + double-talk) and echo-reference WAVs."""
    rate = args.rate
    far_a = mix_signals(
        make_multitone(rate, 2.5, (420.0, 710.0, 1380.0, 2150.0), -10.0),
        make_noise(rate, 2.5, -26.0, rng),
    )
    far_b = mix_signals(
        make_multitone(rate, 2.5, (420.0, 710.0, 1380.0, 2150.0), -10.0),
        make_noise(rate, 2.5, -26.0, rng),
    )
    ref_full = header + far_a + far_b

    delay_samples = int(round((args.echo_delay_ms / 1000.0) * rate))
    echo_gain = db_to_amp(args.echo_gain_db)
    mic_full = [
        echo_gain * ref_full[i - delay_samples] if i >= delay_samples else 0.0
        for i in range(len(ref_full))
    ]

    near_start = int(round((SYNC_HEADER_SEC + 2.5) * rate))
    for i, val in enumerate(make_sine(rate, 2.5, 997.0, -14.0)):
        idx = near_start + i
        if idx < len(mic_full):
            mic_full[idx] = max(-0.999, min(0.999, mic_full[idx] + val))

    # Include un-delayed sync chirp in mic too for SSP loopback alignment.
    chirp_start = int(round(SYNC_PRE_SEC * rate))
    for i, val in enumerate(make_chirp(rate)):
        idx = chirp_start + i
        if idx < len(mic_full):
            mic_full[idx] = max(-0.999, min(0.999, val))

    write_wav(args.out_mic, mic_full, rate, args.channels, args.format)
    write_wav(args.out_ref, ref_full, rate, args.channels, args.format)


def generate_profile(args):
    """Generate labeled stimulus WAV(s) for requested WebRTC profile."""
    profile = args.profile
    rate = args.rate
    rng = random.Random(PRNG_SEED)
    header = build_sync_header(rate)

    if profile == "hpf":
        payload = mix_signals(
            make_sine(rate, args.duration, 40.0, -8.0),
            make_sine(rate, args.duration, 1000.0, -14.0),
        )
        write_wav(args.output, header + payload, rate, args.channels, args.format)
        return

    if profile in ("ns", "ns2"):
        noise_seg = make_noise(rate, 2.5, -20.0, rng)
        speech_seg = mix_signals(
            make_multitone(rate, 2.0, (350.0, 1000.0, 2200.0), -10.0),
            make_noise(rate, 2.0, -24.0, rng),
        )
        write_wav(
            args.output,
            header + noise_seg + speech_seg,
            rate,
            args.channels,
            args.format,
        )
        return

    if profile == "agc":
        payload = make_sine(rate, 2.0, 1000.0, -34.0) + make_sine(rate, 2.0, 1000.0, -1.0)
        write_wav(args.output, header + payload, rate, args.channels, args.format)
        return

    if profile == "vad":
        sil1 = [0.0] * int(round(1.2 * rate))
        sp1 = make_multitone(rate, 1.2, (450.0, 1000.0, 1900.0), -12.0)
        sil2 = [0.0] * int(round(1.0 * rate))
        sp2 = mix_signals(
            make_multitone(rate, 1.0, (450.0, 1000.0), -14.0),
            make_noise(rate, 1.0, -28.0, rng),
        )
        write_wav(
            args.output,
            header + sil1 + sp1 + sil2 + sp2,
            rate,
            args.channels,
            args.format,
        )
        return

    if profile == "aec":
        _generate_aec_pair(args, rng, header)
        return

    raise ValueError(f"Unsupported profile {profile}")


def _refine_chirp_window(sig_slice, pat, lo_idx, hi_idx, use_numpy):
    """Exact sample-level normalized cross-correlation inside [lo_idx, hi_idx]."""
    pat_e = sum(x * x for x in pat)
    best_pos = lo_idx
    best_score = -1.0
    for pos in range(lo_idx, hi_idx + 1):
        seg = sig_slice[pos : pos + len(pat)]
        if use_numpy:
            dot = float(np.dot(seg, pat))
            seg_e = float(np.dot(seg, seg))
        else:
            dot = sum(a * b for a, b in zip(seg, pat))
            seg_e = sum(a * a for a in seg)
        score = dot / math.sqrt(max(seg_e * pat_e, 1e-12))
        if score > best_score:
            best_score = score
            best_pos = pos
    return best_pos, best_score


def _find_chirp_numpy(samples, chirp, search_end):
    """Coarse-to-fine sync chirp search backed by numpy."""
    sig = np.asarray(samples[:search_end], dtype=np.float64)
    pat = np.asarray(chirp, dtype=np.float64)
    step = 4
    sig_d = sig[::step]
    pat_d = pat[::step]
    corr = np.correlate(sig_d, pat_d, mode="valid")
    sig_sq = np.convolve(sig_d * sig_d, np.ones(len(pat_d)), mode="valid")
    denom = np.sqrt(np.maximum(sig_sq * float(np.dot(pat_d, pat_d)), 1e-12))
    coarse_idx = int(np.argmax(corr / denom)) * step
    return _refine_chirp_window(
        sig, pat, max(0, coarse_idx - 32), min(search_end - len(pat), coarse_idx + 32), True
    )


def _find_chirp_py(samples, chirp, search_end):
    """Coarse-to-fine sync chirp search in pure Python."""
    dec = 8
    pat_d = chirp[::dec]
    pat_e = sum(x * x for x in pat_d)
    sig_d = samples[:search_end:dec]
    best_coarse = 0
    best_val = -1.0
    for pos in range(0, max(1, len(sig_d) - len(pat_d)), 2):
        seg = sig_d[pos : pos + len(pat_d)]
        dot = sum(a * b for a, b in zip(seg, pat_d))
        seg_e = sum(a * a for a in seg)
        score = dot / math.sqrt(max(seg_e * pat_e, 1e-12))
        if score > best_val:
            best_val = score
            best_coarse = pos * dec
    return _refine_chirp_window(
        samples,
        chirp,
        max(0, best_coarse - 32),
        min(search_end - len(chirp), best_coarse + 32),
        False,
    )


def find_chirp_offset(samples, rate, max_search_sec=5.0):
    """Locate sync chirp start sample using normalized cross-correlation."""
    chirp = make_chirp(rate)
    search_end = min(len(samples), int(round(max_search_sec * rate)))
    if search_end <= len(chirp) + 16:
        raise RuntimeError(
            f"Captured audio too short ({len(samples)} samples) to locate sync chirp"
        )
    if np is not None:
        return _find_chirp_numpy(samples, chirp, search_end)
    return _find_chirp_py(samples, chirp, search_end)


def slice_after_header(samples, rate, start_sec, dur_sec):
    """Locate sync chirp and slice payload window relative to payload start."""
    chirp_idx, score = find_chirp_offset(samples, rate)
    if score < 0.25:
        raise RuntimeError(
            f"Sync chirp correlation too weak ({score:.3f} < 0.25); check audio path"
        )
    payload_start = chirp_idx + int(round((SYNC_CHIRP_SEC + SYNC_POST_SEC) * rate))
    s0 = payload_start + int(round(start_sec * rate))
    s1 = payload_start + int(round((start_sec + dur_sec) * rate))
    if s1 > len(samples):
        raise RuntimeError(
            f"Capture truncated: need sample {s1} ({s1 / rate:.2f}s), got {len(samples)}"
        )
    return samples[s0:s1], score


def check_no_dropouts(samples, rate, label):
    """Verify active segment contains no unexpected 20ms digital-zero dropouts."""
    win = max(1, int(0.02 * rate))
    overall = rms_db(samples)
    if overall < -60.0:
        return
    silent_frames = 0
    total_frames = len(samples) // win
    for idx in range(total_frames):
        sub = samples[idx * win : (idx + 1) * win]
        if rms_db(sub) < overall - 30.0:
            silent_frames += 1
    if silent_frames > 1:
        raise RuntimeError(
            f"Detected {silent_frames}/{total_frames} dropout frames in '{label}'"
        )


def analyze_hpf(cap, rate, base, args):
    """Verify >= 12 dB attenuation at 40 Hz and <= 2.5 dB passband loss at 1 kHz."""
    seg, score = slice_after_header(cap, rate, 0.3, args.duration - 0.5)
    check_no_dropouts(seg, rate, "hpf")
    p40 = goertzel_power_db(seg, rate, 40.0)
    p1k = goertzel_power_db(seg, rate, 1000.0)

    if base is not None:
        bseg, bscore = slice_after_header(base, rate, 0.3, args.duration - 0.5)
        b40 = goertzel_power_db(bseg, rate, 40.0)
        b1k = goertzel_power_db(bseg, rate, 1000.0)
        atten_40 = b40 - p40
        pass_delta = p1k - b1k
        print(
            f"HPF sync={score:.3f}/{bscore:.3f} p40={p40:.2f}dB (off {b40:.2f}dB) "
            f"atten_40Hz={atten_40:.2f}dB p1k_delta={pass_delta:+.2f}dB"
        )
        if atten_40 < args.min_hpf_atten_db:
            raise RuntimeError(
                f"40 Hz attenuation {atten_40:.2f} dB < {args.min_hpf_atten_db:.1f} dB"
            )
        if abs(pass_delta) > 2.5:
            raise RuntimeError(f"1 kHz passband drift {pass_delta:+.2f} dB > 2.5 dB")
    else:
        rel_rej = p1k - p40
        print(
            f"HPF sync={score:.3f} p40={p40:.2f}dB p1k={p1k:.2f}dB (1k-40={rel_rej:.2f}dB)"
        )
        if rel_rej < args.min_hpf_atten_db:
            raise RuntimeError(
                f"HPF relative rejection (1kHz-40Hz) {rel_rej:.2f} dB < {args.min_hpf_atten_db:.1f} dB"
            )


def analyze_ns(cap, rate, args):
    """Verify noise attenuation after convergence while preserving speech tones."""
    early_noise, score = slice_after_header(cap, rate, 0.05, 0.25)
    steady_noise, _ = slice_after_header(cap, rate, 1.4, 1.0)
    speech_seg, _ = slice_after_header(cap, rate, 2.8, 1.4)
    check_no_dropouts(speech_seg, rate, args.profile)

    early_db = rms_db(early_noise)
    noise_db = rms_db(steady_noise)
    tone_1k_db = goertzel_power_db(speech_seg, rate, 1000.0)
    snr_gain_db = tone_1k_db - noise_db
    print(
        f"{args.profile.upper()} sync={score:.3f} early_noise={early_db:.2f}dB "
        f"steady_noise={noise_db:.2f}dB tone_1k={tone_1k_db:.2f}dB "
        f"SNR={snr_gain_db:.2f}dB"
    )
    if snr_gain_db < args.min_snr_gain_db:
        raise RuntimeError(
            f"NS speech-to-noise ratio {snr_gain_db:.2f} dB < {args.min_snr_gain_db:.1f} dB"
        )
    if tone_1k_db < -40.0:
        raise RuntimeError(f"NS speech tone collapsed ({tone_1k_db:.2f} dB)")


def _agc_segment_levels(samples, rate):
    """Extract sync score, quiet RMS, loud RMS, and loud peak dBFS for AGC."""
    quiet_seg, score = slice_after_header(samples, rate, 0.5, 1.2)
    loud_seg, _ = slice_after_header(samples, rate, 2.5, 1.2)
    check_no_dropouts(quiet_seg, rate, "agc_quiet")
    check_no_dropouts(loud_seg, rate, "agc_loud")
    return score, rms_db(quiet_seg), rms_db(loud_seg), peak_db(loud_seg)


def analyze_agc(cap, rate, base, args):
    """Verify AGC quiet-signal boost and loud-signal peak limiting."""
    score, q_on_db, l_on_db, l_peak_db = _agc_segment_levels(cap, rate)
    dyn_on = l_on_db - q_on_db

    if base is not None:
        bscore, q_off_db, l_off_db, _ = _agc_segment_levels(base, rate)
        comp_db = (l_off_db - q_off_db) - dyn_on
        print(
            f"AGC sync={score:.3f}/{bscore:.3f} quiet={q_on_db:.2f}dB(off {q_off_db:.2f}dB) "
            f"loud={l_on_db:.2f}dB(off {l_off_db:.2f}dB) peak={l_peak_db:.2f}dBFS "
            f"compression={comp_db:.2f}dB"
        )
        if comp_db < args.min_agc_comp_db:
            raise RuntimeError(
                f"AGC dynamic compression {comp_db:.2f} dB < {args.min_agc_comp_db:.1f} dB"
            )
    else:
        print(
            f"AGC sync={score:.3f} quiet={q_on_db:.2f}dB loud={l_on_db:.2f}dB "
            f"peak={l_peak_db:.2f}dBFS span={dyn_on:.2f}dB"
        )
        if dyn_on > 26.0:
            raise RuntimeError(f"AGC dynamic span {dyn_on:.2f} dB too wide (>26 dB)")

    if l_peak_db > -0.05:
        raise RuntimeError(f"AGC loud segment clipped (peak {l_peak_db:.2f} dBFS)")


def analyze_vad(cap, rate):
    """Verify VAD transparency between silence and speech bursts."""
    sil1, score = slice_after_header(cap, rate, 0.15, 0.9)
    sp1, _ = slice_after_header(cap, rate, 1.35, 0.9)
    sil2, _ = slice_after_header(cap, rate, 2.55, 0.7)
    sp2, _ = slice_after_header(cap, rate, 3.55, 0.7)
    check_no_dropouts(sp1, rate, "vad_speech1")
    check_no_dropouts(sp2, rate, "vad_speech2")

    sil_max = max(rms_db(sil1), rms_db(sil2))
    sp_min = min(rms_db(sp1), rms_db(sp2))
    contrast = sp_min - sil_max
    print(
        f"VAD sync={score:.3f} silence_max={sil_max:.2f}dB "
        f"speech_min={sp_min:.2f}dB contrast={contrast:.2f}dB"
    )
    if contrast < 20.0:
        raise RuntimeError(f"VAD silence/speech contrast {contrast:.2f} dB < 20.0 dB")


def _aec_segment_levels(samples, rate):
    """Extract sync score, single-talk far-end RMS, and double-talk 997 Hz power."""
    far_seg, score = slice_after_header(samples, rate, 0.8, 1.5)
    dt_seg, _ = slice_after_header(samples, rate, 2.8, 2.0)
    check_no_dropouts(dt_seg, rate, "aec_double_talk")
    return score, rms_db(far_seg), goertzel_power_db(dt_seg, rate, 997.0)


def analyze_aec(cap, rate, base, args):
    """Verify single-talk ERLE and double-talk near-end preservation."""
    score, far_on_db, near_on_997 = _aec_segment_levels(cap, rate)

    if base is not None:
        bscore, far_off_db, near_off_997 = _aec_segment_levels(base, rate)
        erle_db = far_off_db - far_on_db
        near_delta = near_on_997 - near_off_997
        print(
            f"AEC sync={score:.3f}/{bscore:.3f} far_on={far_on_db:.2f}dB "
            f"(off {far_off_db:.2f}dB) ERLE={erle_db:.2f}dB "
            f"near_997_delta={near_delta:+.2f}dB"
        )
        if erle_db < args.min_erle_db:
            raise RuntimeError(f"AEC ERLE {erle_db:.2f} dB < {args.min_erle_db:.1f} dB")
        if not args.single_talk_only and near_delta < -6.0:
            raise RuntimeError(
                f"AEC attenuated near-end double-talk by {-near_delta:.2f} dB (> 6.0 dB)"
            )
    else:
        if args.single_talk_only:
            print(
                f"AEC sync={score:.3f} far_on={far_on_db:.2f}dB (single-talk baseline missing)"
            )
            return
        ratio = near_on_997 - far_on_db
        print(
            f"AEC sync={score:.3f} far_on={far_on_db:.2f}dB "
            f"near_997={near_on_997:.2f}dB near_to_echo={ratio:.2f}dB"
        )
        if ratio < args.min_erle_db:
            raise RuntimeError(
                f"AEC near-to-residual-echo ratio {ratio:.2f} dB < {args.min_erle_db:.1f} dB"
            )


def analyze_profile(args):
    """Run profile-specific verification on captured WAV."""
    cap, rate, _, _ = read_wav(args.captured)
    base = None
    if args.baseline:
        base, b_rate, _, _ = read_wav(args.baseline)
        if b_rate != rate:
            raise RuntimeError(f"Sample rate mismatch: captured={rate}, baseline={b_rate}")

    if args.profile == "hpf":
        analyze_hpf(cap, rate, base, args)
    elif args.profile in ("ns", "ns2"):
        analyze_ns(cap, rate, args)
    elif args.profile == "agc":
        analyze_agc(cap, rate, base, args)
    elif args.profile == "vad":
        analyze_vad(cap, rate)
    elif args.profile == "aec":
        analyze_aec(cap, rate, base, args)
    else:
        raise ValueError(f"Unsupported profile {args.profile}")


def parse_args():
    """Parse CLI subcommands."""
    parser = argparse.ArgumentParser(description="WebRTC sof-test stimulus & analysis tool")
    sub = parser.add_subparsers(dest="cmd", required=True)

    gen = sub.add_parser("generate", help="Generate deterministic WebRTC test WAV(s)")
    gen.add_argument("--profile", required=True, choices=("hpf", "ns", "ns2", "agc", "vad", "aec"))
    gen.add_argument("--rate", type=int, default=16000)
    gen.add_argument("--channels", type=int, default=2)
    gen.add_argument("--format", default="S16_LE", choices=("S16_LE", "S32_LE"))
    gen.add_argument("--duration", type=float, default=2.0)
    gen.add_argument("--echo-delay-ms", type=float, default=20.0)
    gen.add_argument("--echo-gain-db", type=float, default=-6.0)
    gen.add_argument("--output", help="Output WAV path (for non-aec profiles)")
    gen.add_argument("--out-mic", help="Output mic WAV path (for aec profile)")
    gen.add_argument("--out-ref", help="Output echo-ref WAV path (for aec profile)")

    ana = sub.add_parser("analyze", help="Analyze captured WebRTC WAV against expectations")
    ana.add_argument("--profile", required=True, choices=("hpf", "ns", "ns2", "agc", "vad", "aec"))
    ana.add_argument("--captured", required=True, help="Captured WAV with feature active")
    ana.add_argument("--baseline", help="Optional baseline WAV captured with switch OFF")
    ana.add_argument("--duration", type=float, default=2.0)
    ana.add_argument("--min-hpf-atten-db", type=float, default=12.0)
    ana.add_argument("--min-snr-gain-db", type=float, default=8.0)
    ana.add_argument("--min-agc-comp-db", type=float, default=6.0)
    ana.add_argument("--min-erle-db", type=float, default=10.0)
    ana.add_argument(
        "--single-talk-only",
        action="store_true",
        help="For AEC loopback without external near-end injection, skip double-talk near-end check",
    )

    return parser.parse_args()


def main():
    """Entry point."""
    args = parse_args()
    if args.cmd == "generate":
        if args.profile == "aec":
            if not args.out_mic or not args.out_ref:
                raise SystemExit("--out-mic and --out-ref are required for aec profile")
        elif not args.output:
            raise SystemExit("--output is required for non-aec profiles")
        generate_profile(args)
        return 0

    analyze_profile(args)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
