#!/bin/bash

# Shared WebRTC test helpers for topology discovery, mixer save/restore,
# and stimulus/capture routing across SSP loopback, local USB audio, and host PC.

WEBRTC_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../tools && pwd)"
export PATH="${WEBRTC_TOOLS_DIR}:${PATH}"

declare -Ag WEBRTC_SAVED_SWITCHES=()

# Discover WebRTC widgets/kcontrols from topology, falling back to amixer scan
# Args: $1 = tplg path(s), $2 = filter type (hpf|agc|aec|vad|ns|ns2|all)
func_webrtc_discover_controls()
{
    local tplg_files="${1//:/,}"
    local target_type="${2:-all}"
    local sofcard="${SOFCARD:-0}"
    local out=""

    if command -v topo_webrtc_kcontrols.py >/dev/null 2>&1; then
        out=$(topo_webrtc_kcontrols.py "$tplg_files" --type "$target_type" 2>/dev/null || true)
    fi

    if [ -n "$out" ]; then
        printf '%s\n' "$out"
        return 0
    fi

    # Fallback on minimal DUTs without python3-construct
    local pattern=""
    case "$target_type" in
        hpf) pattern="HPF Switch" ;;
        agc) pattern="AGC Switch" ;;
        aec) pattern="AEC (Suppression )?Switch|webrtc-aec\." ;;
        *)   pattern="(HPF|AGC|AEC (Suppression )?)Switch|webrtc-aec\." ;;
    esac

    amixer -c "$sofcard" controls 2>/dev/null | \
        grep -E "name='.*(${pattern})" | \
        sed -n "s/.*name='\([^']*\)'.*/${target_type}|${target_type}|\1|MIXER/p" || true
}

# Read current integer/boolean switch value from amixer
func_webrtc_get_switch()
{
    local sofcard="$1"
    local ctrl="$2"
    amixer -c "$sofcard" cget "name=${ctrl}" 2>/dev/null | \
        sed -n 's/^  : values=\([0-9]*\).*/\1/p' | head -n1
}

# Save switch state once and set new value (0/1 or off/on)
func_webrtc_set_switch()
{
    local sofcard="$1"
    local ctrl="$2"
    local val="$3"

    if [ -z "${WEBRTC_SAVED_SWITCHES[$ctrl]+x}" ]; then
        local orig
        orig=$(func_webrtc_get_switch "$sofcard" "$ctrl" || true)
        if [ -n "$orig" ]; then
            WEBRTC_SAVED_SWITCHES["$ctrl"]="$orig"
        fi
    fi

    dlogc "amixer -c $sofcard cset name='${ctrl}' ${val}"
    amixer -c "$sofcard" cset "name=${ctrl}" "$val" >/dev/null ||
        die "Failed to set switch '${ctrl}' to '${val}' on card ${sofcard}"

    local expected="0"
    if [ "$val" = "1" ] || [ "$val" = "on" ]; then
        expected="1"
    fi
    local actual
    actual=$(func_webrtc_get_switch "$sofcard" "$ctrl" || true)
    [ "$actual" = "$expected" ] ||
        die "Readback mismatch for '${ctrl}': expected ${expected}, got '${actual}'"
}

func_webrtc_restore_switches()
{
    local sofcard="${SOFCARD:-0}"
    local ctrl
    for ctrl in "${!WEBRTC_SAVED_SWITCHES[@]}"; do
        dlogi "Restoring control '${ctrl}' = ${WEBRTC_SAVED_SWITCHES[$ctrl]}"
        amixer -c "$sofcard" cset "name=${ctrl}" "${WEBRTC_SAVED_SWITCHES[$ctrl]}" >/dev/null 2>&1 || true
    done
}

# Resolve non-SOF local USB audio playback/capture PCM (e.g. plughw:1,0)
func_webrtc_detect_usb_pcm()
{
    local explicit_pcm="$1"
    local sofcard="${SOFCARD:-0}"

    if [ -n "$explicit_pcm" ]; then
        printf '%s\n' "$explicit_pcm"
        return 0
    fi
    if [ -n "${WEBRTC_USB_PCM:-}" ]; then
        printf '%s\n' "$WEBRTC_USB_PCM"
        return 0
    fi

    local card_idx
    card_idx=$(awk -v sc="$sofcard" '
        /^[[:space:]]*[0-9]+ \[/ {
            c = $1 + 0
            line = $0
            if (c != sc && tolower(line) ~ /usb/) {
                print c
                exit
            }
        }
    ' /proc/asound/cards 2>/dev/null || true)

    [ -n "$card_idx" ] || return 1
    printf 'plughw:%s,0\n' "$card_idx"
}

# Find first capture pipeline matching optional PCM substring
# Sets globals: WEBRTC_CAP_DEV WEBRTC_CAP_RATE WEBRTC_CAP_FMT WEBRTC_CAP_CH WEBRTC_CAP_PCM
func_webrtc_select_capture_pipeline()
{
    local tplg="$1"
    local cap_filter="${2:-type:capture}"
    local preferred_pcm="${3:-}"

    func_pipeline_export "$tplg" "$cap_filter"
    local chosen=0 idx pcm_name
    if [ -n "$preferred_pcm" ]; then
        for idx in $(seq 0 $((PIPELINE_COUNT - 1))); do
            pcm_name=$(func_pipeline_parse_value "$idx" pcm)
            if [[ "$pcm_name" == *"$preferred_pcm"* ]]; then
                chosen="$idx"
                break
            fi
        done
    fi

    WEBRTC_CAP_DEV=$(func_pipeline_parse_value "$chosen" dev)
    WEBRTC_CAP_RATE=$(func_pipeline_parse_value "$chosen" rate)
    WEBRTC_CAP_FMT=$(func_pipeline_parse_value "$chosen" fmt)
    WEBRTC_CAP_CH=$(func_pipeline_parse_value "$chosen" ch_min)
    WEBRTC_CAP_PCM=$(func_pipeline_parse_value "$chosen" pcm)
    [ -n "$WEBRTC_CAP_DEV" ] || die "Failed to select capture pipeline"
}

# Run synchronized stimulus playback + capture for non-AEC profiles
# Args: $1=io_mode (ssp|usb|host), $2=stim_wav, $3=out_wav, $4=dur_sec,
#       $5=tplg, $6=usb_pcm, $7=host_cmd
func_webrtc_capture_stimulus()
{
    local io_mode="$1"
    local stim_wav="$2"
    local out_wav="$3"
    local dur_sec="$4"
    local tplg="$5"
    local usb_pcm="$6"
    local host_cmd="$7"

    rm -f "$out_wav"
    dlogc "arecord -D $WEBRTC_CAP_DEV -f $WEBRTC_CAP_FMT -r $WEBRTC_CAP_RATE -c $WEBRTC_CAP_CH -d $dur_sec $out_wav"
    arecord -D "$WEBRTC_CAP_DEV" -f "$WEBRTC_CAP_FMT" -r "$WEBRTC_CAP_RATE" \
        -c "$WEBRTC_CAP_CH" -d "$dur_sec" "$out_wav" &
    local rec_pid=$!
    sleep 0.25

    local play_rc=0
    case "$io_mode" in
        ssp)
            local pb_dev="" idx pb_pcm
            func_pipeline_export "$tplg" "type:playback"
            for idx in $(seq 0 $((PIPELINE_COUNT - 1))); do
                pb_pcm=$(func_pipeline_parse_value "$idx" pcm)
                if [ "$pb_pcm" = "$WEBRTC_CAP_PCM" ] || [ -z "$pb_dev" ]; then
                    pb_dev=$(func_pipeline_parse_value "$idx" dev)
                    [ "$pb_pcm" = "$WEBRTC_CAP_PCM" ] && break
                fi
            done
            [ -n "$pb_dev" ] || {
                kill "$rec_pid" 2>/dev/null || true
                wait "$rec_pid" 2>/dev/null || true
                die "No playback pipeline found for SSP loopback mode"
            }
            dlogc "aplay -D $pb_dev $stim_wav"
            aplay -D "$pb_dev" "$stim_wav" || play_rc=$?
            ;;
        usb)
            local resolved_usb
            resolved_usb=$(func_webrtc_detect_usb_pcm "$usb_pcm") || {
                kill "$rec_pid" 2>/dev/null || true
                wait "$rec_pid" 2>/dev/null || true
                skip_test "No USB audio device found (pass -U plughw:N,0)"
            }
            dlogc "aplay -D $resolved_usb $stim_wav"
            aplay -D "$resolved_usb" "$stim_wav" || play_rc=$?
            ;;
        host)
            local cmd_tpl="${host_cmd:-${WEBRTC_HOST_PLAY_CMD:-}}"
            [ -n "$cmd_tpl" ] || {
                kill "$rec_pid" 2>/dev/null || true
                wait "$rec_pid" 2>/dev/null || true
                skip_test "Host mode requires -H '<cmd>' or WEBRTC_HOST_PLAY_CMD"
            }
            if [[ "$cmd_tpl" == *"{wav}"* ]]; then
                local expanded="${cmd_tpl//\{wav\}/\"$stim_wav\"}"
                dlogc "$expanded"
                eval "$expanded" || play_rc=$?
            else
                dlogc "$cmd_tpl < $stim_wav"
                eval "$cmd_tpl" < "$stim_wav" || play_rc=$?
            fi
            ;;
        *)
            kill "$rec_pid" 2>/dev/null || true
            wait "$rec_pid" 2>/dev/null || true
            die "Unsupported io_mode '$io_mode'"
            ;;
    esac

    local rec_rc=0
    wait "$rec_pid" || rec_rc=$?
    [ "$play_rc" -eq 0 ] || die "Stimulus playback failed (rc=$play_rc, mode=$io_mode)"
    [ "$rec_rc" -eq 0 ] || die "DUT capture failed on $WEBRTC_CAP_DEV (rc=$rec_rc)"
    [ -s "$out_wav" ] || die "Captured WAV $out_wav is empty"
}

func_webrtc_on_exit()
{
    local rc="$1"
    func_webrtc_restore_switches
    func_exit_handler "$rc"
}

# Preserve lib.sh func_exit_handler while guaranteeing mixer switches restore on exit
func_webrtc_register_cleanup()
{
    trap 'func_webrtc_on_exit "$?"' EXIT SIGTERM
}
