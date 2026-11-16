#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Shared helpers for SOF compressed audio (FFmpeg decoder/encoder) tests.

export COMPR_DECODE_CODECS_ALL="flac mp3 aac opus alac sbc msbc g722 aptx"
export COMPR_ENCODE_CODECS_ALL="mp3 aac flac alac sbc msbc g722 aptx"

COMPR_TOOL="${COMPR_TOOL:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/tools/sof-compr-tool.py}"

# Check whether an external CLI helper is available in PATH or executable
func_compr_has_bin()
{
    local bin="$1"
    command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ]
}

# Print default test parameters for a codec:
#   "<rate> <channels> <bitrate> <fmt> <cplay_hex_or_name> <crecord_hex>"
func_compr_codec_defaults()
{
    local codec="${1,,}"
    case "$codec" in
        flac)
            echo "48000 2 0 S16_LE FLAC 0x0A"
            ;;
        mp3)
            echo "48000 2 192000 S16_LE MP3 0x02"
            ;;
        aac)
            echo "48000 2 192000 S16_LE AAC 0x06"
            ;;
        opus|opus_raw)
            echo "48000 2 128000 S16_LE NONE 0x11"
            ;;
        alac)
            echo "48000 2 0 S16_LE NONE 0x0F"
            ;;
        sbc)
            echo "48000 2 328000 S16_LE NONE 0x12"
            ;;
        msbc)
            echo "16000 1 64000 S16_LE NONE 0x12"
            ;;
        g722)
            echo "16000 1 64000 S16_LE NONE 0x13"
            ;;
        aptx)
            echo "48000 2 384000 S16_LE NONE 0x14"
            ;;
        *)
            dloge "Unknown compressed codec: $codec"
            return 1
            ;;
    esac
}

# Parse hardware card and compress device id from pipeline device or /dev/snd node
# Sets global variables COMPR_CARD and COMPR_DEV
func_compr_parse_dev()
{
    local dev_str="$1"
    if [[ "$dev_str" =~ comprC([0-9]+)D([0-9]+) ]]; then
        COMPR_CARD="${BASH_REMATCH[1]}"
        COMPR_DEV="${BASH_REMATCH[2]}"
        return 0
    fi
    if [[ "$dev_str" =~ ([0-9]+),([0-9]+) ]]; then
        COMPR_CARD="${BASH_REMATCH[1]}"
        COMPR_DEV="${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

# Query whether a compress device advertises support for <codec>
# Returns: 0=supported, 1=unsupported codec (rc=2 from tool), 2=device/ioctl error
func_compr_dev_supports_codec()
{
    local snd_dev="$1"
    local direction="$2"
    local codec="$3"
    local caps_out
    local rc=0

    caps_out=$(python3 "$COMPR_TOOL" caps -D "$snd_dev" --direction "$direction" \
        --has-codec "$codec" 2>&1) || rc=$?
    if [ "$rc" -eq 0 ]; then
        return 0
    fi
    if [ "$rc" -eq 2 ]; then
        return 1
    fi
    dloge "Compress capability query failed on $snd_dev ($direction, codec=$codec, rc=$rc): $caps_out"
    return 2
}

# Check if cplay supports the given codec
func_compr_cplay_supports()
{
    local codec="${1,,}"
    func_compr_has_bin cplay || return 1
    case "$codec" in
        mp3|aac)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if crecord supports the given codec
func_compr_crecord_supports()
{
    local codec="${1,,}"
    func_compr_has_bin crecord || return 1
    case "$codec" in
        flac)
            # Upstream tinycompress crecord sets codec.format to S16_LE (0x2);
            # among compressed encoders only ffmpeg-enc-flac/alac accept 0x2,
            # and crecord only exposes FLAC in its codec name table.
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Generate a compressed sine-wave test vector using ffmpeg
func_compr_gen_vector()
{
    local codec="${1,,}"
    local out_file="$2"
    local duration="${3:-3}"
    local freq="${4:-997}"

    func_compr_has_bin ffmpeg || {
        dloge "ffmpeg is required to generate compressed test vectors"
        return 1
    }

    local defaults
    defaults=$(func_compr_codec_defaults "$codec") || return 1
    local rate ch bitrate
    read -r rate ch bitrate _ _ _ <<< "$defaults"

    local src_spec="sine=frequency=${freq}:sample_rate=${rate}:duration=${duration}"
    local -a cmd=(ffmpeg -y -v error -f lavfi -i "$src_spec" -ac "$ch" -ar "$rate")

    case "$codec" in
        flac)
            cmd+=(-c:a flac -f flac "$out_file")
            ;;
        mp3)
            cmd+=(-c:a libmp3lame -b:a "$bitrate" -f mp3 "$out_file")
            ;;
        aac)
            cmd+=(-c:a aac -b:a "$bitrate" -f adts "$out_file")
            ;;
        opus|opus_raw)
            cmd+=(-c:a libopus -b:a "$bitrate" -f opus "$out_file")
            ;;
        alac)
            cmd+=(-c:a alac -f mp4 "$out_file")
            ;;
        sbc)
            cmd+=(-c:a sbc -b:a "$bitrate" -f sbc "$out_file")
            ;;
        msbc)
            cmd+=(-c:a sbc -msbc 1 -f sbc "$out_file")
            ;;
        g722)
            cmd+=(-c:a g722 -f g722 "$out_file")
            ;;
        aptx)
            cmd+=(-c:a aptx -f aptx "$out_file")
            ;;
        *)
            dloge "Unsupported codec for vector generation: $codec"
            return 1
            ;;
    esac

    "${cmd[@]}"
}

# Validate encoded compressed stream magic/sync header and decode to WAV via ffmpeg
func_compr_verify_encoded_file()
{
    local codec="${1,,}"
    local in_file="$2"
    local out_wav="${3:-}"
    local min_bytes="${4:-256}"

    [ -s "$in_file" ] || {
        dloge "Encoded output file is missing or empty: $in_file"
        return 1
    }

    local fsize
    fsize=$(stat -c%s "$in_file")
    if [ "$fsize" -lt "$min_bytes" ]; then
        dloge "Encoded output too small ($fsize B < $min_bytes B): $in_file"
        return 1
    fi

    # Check container / bitstream header sync
    python3 - "$codec" "$in_file" <<'EOF' || return 1
import sys

codec = sys.argv[1].lower()
path = sys.argv[2]
with open(path, "rb") as f:
    head = f.read(64)

if len(head) < 4:
    raise SystemExit(f"{codec}: file header shorter than 4 bytes")

if codec == "flac":
    if not head.startswith(b"fLaC"):
        raise SystemExit(f"flac: expected b'fLaC' magic, got {head[:8]!r}")
elif codec == "alac":
    if b"alac" not in head[:40]:
        raise SystemExit(f"alac: expected 'alac' atom in cookie, got {head[:40]!r}")
elif codec == "aac":
    if not (head[0] == 0xFF and (head[1] & 0xF0) == 0xF0):
        raise SystemExit(f"aac: expected ADTS sync 0xFFFx, got {head[:4].hex()}")
elif codec == "mp3":
    is_sync = head[0] == 0xFF and (head[1] & 0xE0) == 0xE0
    if not is_sync and not head.startswith(b"ID3"):
        raise SystemExit(f"mp3: expected frame sync/ID3, got {head[:4].hex()}")
elif codec == "sbc":
    if head[0] != 0x9C:
        raise SystemExit(f"sbc: expected syncword 0x9c, got 0x{head[0]:02x}")
elif codec == "msbc":
    if head[0] != 0xAD:
        raise SystemExit(f"msbc: expected syncword 0xad, got 0x{head[0]:02x}")
elif codec in ("g722", "aptx", "opus", "opus_raw"):
    if all(b == 0 for b in head[:32]):
        raise SystemExit(f"{codec}: output begins with 32 zero bytes")
EOF

    func_compr_has_bin ffmpeg || {
        dlogw "ffmpeg not found; skipping host decode verification for $codec"
        return 0
    }

    local defaults
    defaults=$(func_compr_codec_defaults "$codec") || return 1
    local rate ch
    read -r rate ch _ _ _ _ <<< "$defaults"

    local tmp_wav="${out_wav:-${in_file}.decoded.wav}"
    local -a dec_cmd=(ffmpeg -y -v error)
    local dec_input="$in_file"

    case "$codec" in
        flac)
            dec_cmd+=(-f flac -i "$dec_input")
            ;;
        mp3)
            dec_cmd+=(-f mp3 -i "$dec_input")
            ;;
        aac)
            dec_cmd+=(-f aac -i "$dec_input")
            ;;
        sbc|msbc)
            dec_cmd+=(-f sbc -i "$dec_input")
            ;;
        g722)
            dec_cmd+=(-f g722 -i "$dec_input")
            ;;
        aptx)
            dec_cmd+=(-f aptx -ar "$rate" -ac "$ch" -i "$dec_input")
            ;;
        alac)
            # ffmpeg_enc-alac writes a 36-byte QuickTime 'alac' atom + raw
            # variable-size frames; FFmpeg's CAF demuxer requires a 'pakt'
            # packet-size table to decode CAF-wrapped variable-size ALAC, so
            # only invoke ffmpeg -f caf when the capture already starts with
            # a full 'caff' container, and validate the ALAC cookie + payload
            # directly for raw SOF ALAC captures.
            local caf_file="${in_file}.caf"
            local alac_mode
            alac_mode=$(python3 - "$in_file" "$caf_file" "$rate" "$ch" <<'EOF'
import struct, sys

in_path, out_path, rate, ch = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
with open(in_path, "rb") as f:
    raw = f.read()

if raw[:4] == b"caff":
    with open(out_path, "wb") as out:
        out.write(raw)
    print("caf")
    sys.exit(0)

# Expect 36-byte ALAC magic cookie (atom size + 'alac' + version/flags + 24B config)
if len(raw) < 40 or raw[4:8] != b"alac":
    raise SystemExit(f"Unexpected ALAC stream prefix: {raw[:16].hex()}")

cookie_size = struct.unpack(">I", raw[:4])[0]
if cookie_size != 36:
    raise SystemExit(f"Unexpected ALAC atom size {cookie_size}, expected 36")

cookie = raw[:36]
payload = raw[36:]
frame_len = struct.unpack(">I", cookie[12:16])[0]
bit_depth = cookie[17]
cookie_ch = cookie[21]
cookie_rate = struct.unpack(">I", cookie[32:36])[0]
if frame_len == 0 or bit_depth not in (16, 24, 32):
    raise SystemExit(f"Invalid ALAC config frame_len={frame_len} bit_depth={bit_depth}")
if cookie_ch != ch or cookie_rate != rate:
    raise SystemExit(f"ALAC header mismatch: ch={cookie_ch} rate={cookie_rate} vs {ch}/{rate}")
if len(payload) < 32 or all(b == 0 for b in payload[:32]):
    raise SystemExit(f"Invalid ALAC payload (len={len(payload)})")

print(f"raw {len(payload)} {frame_len} {bit_depth}")
EOF
) || return 1
            if [ "${alac_mode%% *}" != "caf" ]; then
                dlogi "Verified alac magic cookie + raw frames ($fsize B, ${alac_mode#raw })"
                [ -n "$out_wav" ] && rm -f "$out_wav"
                return 2
            fi
            dec_input="$caf_file"
            dec_cmd+=(-f caf -i "$dec_input")
            ;;
        *)
            dec_cmd+=(-i "$dec_input")
            ;;
    esac

    dec_cmd+=("$tmp_wav")
    if ! "${dec_cmd[@]}"; then
        dloge "ffmpeg failed to decode $codec output ($in_file)"
        return 1
    fi

    [ -s "$tmp_wav" ] || {
        dloge "Decoded WAV for $codec is empty: $tmp_wav"
        return 1
    }

    local wav_dur
    wav_dur=$(python3 - "$tmp_wav" <<'EOF'
import sys, wave
with wave.open(sys.argv[1], "rb") as w:
    frames = w.getnframes()
    rate = w.getframerate()
    print(f"{frames / float(rate):.3f}" if rate else "0")
EOF
)
    dlogi "Verified $codec encoded stream ($fsize B -> decoded WAV ${wav_dur}s)"
    if [ -z "$out_wav" ]; then
        rm -f "$tmp_wav"
    fi
    return 0
}

# Verify a WAV file contains an expected tone frequency (used in loopback checks)
func_compr_verify_wav_tone()
{
    local wav_file="$1"
    local expected_freq="$2"
    local tol_hz="${3:-60}"
    local min_rms="${4:-0.005}"

    python3 - "$wav_file" "$expected_freq" "$tol_hz" "$min_rms" <<'EOF'
import math, struct, sys, wave

path = sys.argv[1]
target_hz = float(sys.argv[2])
tol_hz = float(sys.argv[3])
min_rms = float(sys.argv[4])

with wave.open(path, "rb") as w:
    ch = w.getnchannels()
    width = w.getsampwidth()
    rate = w.getframerate()
    nframes = w.getnframes()
    raw = w.readframes(nframes)

if nframes == 0:
    raise SystemExit("WAV has 0 frames")

fmt_char = {2: "h", 4: "i"}.get(width)
if not fmt_char:
    raise SystemExit(f"Unsupported WAV sample width: {width}")

scale = float(1 << (8 * width - 1))
samples = struct.unpack(f"<{nframes * ch}{fmt_char}", raw)
mono = [samples[i] / scale for i in range(0, len(samples), ch)]
rms = math.sqrt(sum(s * s for s in mono) / len(mono))
if rms < min_rms:
    raise SystemExit(f"WAV RMS {rms:.5f} below minimum threshold {min_rms}")

try:
    import numpy as np
    win = np.array(mono[: min(len(mono), rate * 2)], dtype=np.float64)
    win -= np.mean(win)
    spec = np.abs(np.fft.rfft(win * np.hanning(len(win))))
    freqs = np.fft.rfftfreq(len(win), 1.0 / rate)
    peak_hz = float(freqs[int(np.argmax(spec))])
    if abs(peak_hz - target_hz) > tol_hz:
        raise SystemExit(f"Peak freq {peak_hz:.1f}Hz != expected {target_hz:.1f}Hz (+/-{tol_hz})")
    print(f"Tone verified: peak={peak_hz:.1f}Hz rms={rms:.4f}")
except ImportError:
    print(f"RMS verified (no numpy for FFT): rms={rms:.4f}")
EOF
}

# Play compressed file with either cplay or sof-compr-tool.py
func_compr_run_play()
{
    local tool_mode="$1"
    local snd_dev="$2"
    local codec="$3"
    local in_file="$4"
    local pause_cycles="${5:-0}"
    local duration="${6:-0}"

    if [ "$tool_mode" = "cplay" ] && [ "$pause_cycles" -gt 0 ]; then
        dloge "cplay mode does not support pause/resume cycles ($pause_cycles); use compr-tool"
        return 1
    fi

    local defaults
    defaults=$(func_compr_codec_defaults "$codec") || return 1
    local rate ch bitrate fmt cplay_codec _
    read -r rate ch bitrate fmt cplay_codec _ <<< "$defaults"

    local watchdog=30
    if [ "$duration" -gt 0 ] 2>/dev/null; then
        watchdog=$((duration + 30))
    fi
    if [ "$pause_cycles" -gt 0 ] 2>/dev/null; then
        watchdog=$((watchdog + pause_cycles * 2))
    fi

    if [ "$tool_mode" = "cplay" ] || { [ "$tool_mode" = "auto" ] && [ "$pause_cycles" -eq 0 ] && func_compr_cplay_supports "$codec"; }; then
        func_compr_parse_dev "$snd_dev" || {
            dloge "Cannot parse card/dev from $snd_dev for cplay"
            return 1
        }
        dlogc "timeout -k 5 -s INT $watchdog cplay -c $COMPR_CARD -d $COMPR_DEV -I $cplay_codec $in_file"
        timeout -k 5 -s INT "$watchdog" cplay -c "$COMPR_CARD" -d "$COMPR_DEV" -I "$cplay_codec" "$in_file"
        return $?
    fi

    local -a cmd=(
        timeout -k 5 -s TERM "$watchdog"
        python3 "$COMPR_TOOL" play
        -D "$snd_dev" -C "$codec" -f "$in_file"
        -r "$rate" -n "$ch" -b "$bitrate" --fmt "$fmt"
    )
    if [ "$pause_cycles" -gt 0 ]; then
        cmd+=(--pause-resume "$pause_cycles")
    fi
    dlogc "${cmd[*]}"
    "${cmd[@]}"
}

# Record compressed stream with either crecord or sof-compr-tool.py
func_compr_run_record()
{
    local tool_mode="$1"
    local snd_dev="$2"
    local codec="$3"
    local out_file="$4"
    local duration="${5:-3}"

    local defaults
    defaults=$(func_compr_codec_defaults "$codec") || return 1
    local rate ch bitrate fmt cplay_codec crecord_hex
    read -r rate ch bitrate fmt cplay_codec crecord_hex <<< "$defaults"

    local rec_dur="$duration"
    if [ "$tool_mode" = "crecord" ] || { [ "$tool_mode" = "auto" ] && func_compr_crecord_supports "$codec"; }; then
        func_compr_parse_dev "$snd_dev" || {
            dloge "Cannot parse card/dev from $snd_dev for crecord"
            return 1
        }
        # libtinycompress compress_read() blocks until the full buffer
        # (fragments * fragment_size = 6144 B) fills before writing to stdout.
        if [ "${codec,,}" = "flac" ] && [ "$rec_dur" -lt 15 ]; then
            rec_dur=15
        fi
        local crecord_id="$crecord_hex"
        [ "$cplay_codec" != "NONE" ] && crecord_id="$cplay_codec"
        # Note: crecord computes -l seconds assuming PCM bytes per second and
        # refuses filename arguments for non-PCM codecs; redirect stdout and
        # stop cleanly via SIGINT timeout.
        local -a rec_cmd=(
            timeout -s INT "$rec_dur"
            crecord -c "$COMPR_CARD" -d "$COMPR_DEV"
            -I "$crecord_id" -C "$ch" -R "$rate" -b 6144 -f 3
        )
        dlogc "${rec_cmd[*]} > $out_file"
        local rc=0
        "${rec_cmd[@]}" > "$out_file" || rc=$?
        # timeout returns 124 (or 130 on SIGINT) when duration expires normally
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && [ "$rc" -ne 130 ]; then
            dloge "crecord failed with exit code $rc"
            return "$rc"
        fi
        return 0
    fi

    # Low-bitrate or high-compression capture (silence) needs >1s to fill one
    # 2048-byte compress fragment.
    case "${codec,,}" in
        flac)
            [ "$rec_dur" -lt 5 ] && rec_dur=5
            ;;
        alac|msbc|g722)
            [ "$rec_dur" -lt 3 ] && rec_dur=3
            ;;
    esac

    local -a cmd=(
        python3 "$COMPR_TOOL" record
        -D "$snd_dev" -C "$codec" -o "$out_file"
        -t "$rec_dur" -r "$rate" -n "$ch" -b "$bitrate" --fmt "$fmt"
    )
    dlogc "${cmd[*]}"
    "${cmd[@]}"
}
