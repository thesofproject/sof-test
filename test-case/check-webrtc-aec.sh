#!/bin/bash

set -e

##
## Case Name: check-webrtc-aec
## Preconditions:
##    Topology contains a webrtc-aec widget (nocodec SSP0+SSP2, HDA, or SDW)
## Description:
##    1. Verify capture-only, playback-only, and dynamic mid-stream playback
##       attach/detach lifecycle without capture stalls or XRUNs.
##    2. Verify far-end single-talk ERLE and double-talk near-end preservation
##       across AEC Switch OFF vs ON (and Suppression Switch where present).
##

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh
# shellcheck source=case-lib/webrtc.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/webrtc.sh

OPT_NAME['t']='tplg'       OPT_DESC['t']="tplg file, default value is env TPLG"
OPT_HAS_ARG['t']=1           OPT_VAL['t']="$TPLG"
OPT_NAME['m']='io-mode'    OPT_DESC['m']='Audio mode: ssp | loopback | usb | host'
OPT_HAS_ARG['m']=1           OPT_VAL['m']='ssp'
OPT_NAME['U']='usb-pcm'    OPT_DESC['U']='USB ALSA PCM (for -m usb)'
OPT_HAS_ARG['U']=1           OPT_VAL['U']=''
OPT_NAME['H']='host-cmd'   OPT_DESC['H']='Host play command (for -m host)'
OPT_HAS_ARG['H']=1           OPT_VAL['H']=''
OPT_NAME['d']='delay-ms'   OPT_DESC['d']='Echo path delay(s) in ms (comma-separated)'
OPT_HAS_ARG['d']=1           OPT_VAL['d']='20'
OPT_NAME['R']='ref-ch'     OPT_DESC['R']='Override ref channel count (default: capture ch)'
OPT_HAS_ARG['R']=1           OPT_VAL['R']=''
OPT_NAME['I']='stereo-ind' OPT_DESC['I']='Enable stereo-independent MIMO stimulus/analysis'
OPT_HAS_ARG['I']=0           OPT_VAL['I']=0
OPT_NAME['l']='loop'       OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1           OPT_VAL['l']=1
OPT_NAME['s']='sof-logger' OPT_DESC['s']="Open sof-logger trace stored at $LOG_ROOT"
OPT_HAS_ARG['s']=0           OPT_VAL['s']=1

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
io_mode=${OPT_VAL['m']}
usb_pcm=${OPT_VAL['U']}
host_cmd=${OPT_VAL['H']}
delay_list=${OPT_VAL['d']}
ref_ch_override=${OPT_VAL['R']}
stereo_ind=${OPT_VAL['I']}
loop_cnt=${OPT_VAL['l']}

start_test
func_webrtc_register_cleanup
logger_disabled || func_lib_start_log_collect

func_webrtc_select_capture_pipeline "$tplg" "type:capture"
sofcard="${SOFCARD:-0}"

mapfile -t aec_rows < <(func_webrtc_discover_controls "$TPLG_FILES" "aec")
[ ${#aec_rows[@]} -gt 0 ] || skip_test "No webrtc-aec widget in $TPLG_FILES"

aec_sw=""
aec_sup=""
for row in "${aec_rows[@]}"; do
    IFS='|' read -r _ _ ctrl _ <<< "$row"
    [ -z "$ctrl" ] && continue
    if [[ "$ctrl" == *"Suppression Switch"* ]]; then
        aec_sup="$ctrl"
    else
        aec_sw="$ctrl"
    fi
done

# Discover playback pipeline(s): mic-loopback (PCM 0) and/or echo-ref (PCM 2 / HDA / SDW)
func_pipeline_export "$tplg" "type:playback"
pb_first_dev=$(func_pipeline_parse_value 0 dev)
pb_first_ch=$(func_pipeline_parse_value 0 ch_min)
pb_ref_dev="$pb_first_dev"
pb_mic_dev="$pb_first_dev"
pb_ref_ch="$pb_first_ch"
for idx in $(seq 0 $((PIPELINE_COUNT - 1))); do
    pcm_name=$(func_pipeline_parse_value "$idx" pcm)
    pdev=$(func_pipeline_parse_value "$idx" dev)
    pch=$(func_pipeline_parse_value "$idx" ch_min)
    if [[ "$pcm_name" == *"SSP2"* ]] || [ "$pdev" != "$pb_mic_dev" ]; then
        if [ "$pcm_name" = "$WEBRTC_CAP_PCM" ]; then
            pb_mic_dev="$pdev"
        else
            pb_ref_dev="$pdev"
            pb_ref_ch="$pch"
        fi
    fi
done
[ -n "$pb_ref_dev" ] || die "No playback pipeline found for AEC reference"
ref_ch="${ref_ch_override:-${pb_ref_ch:-$WEBRTC_CAP_CH}}"

stereo_ind_flag=""
if [ "$stereo_ind" -eq 1 ] || { [ "$WEBRTC_CAP_CH" -ge 2 ] && [ "$ref_ch" -ge 2 ]; }; then
    stereo_ind_flag="--stereo-independent"
fi

work_dir="$LOG_ROOT/webrtc-aec"
mkdir -p "$work_dir"

# Phase 1: Single-source / dynamic ref lifecycle (works on every AEC topology)
dlogi "===== AEC Phase 1: capture-only, playback-only, dynamic mid-stream ref ====="
[ -n "$aec_sw" ] && func_webrtc_set_switch "$sofcard" "$aec_sw" on
[ -n "$aec_sup" ] && func_webrtc_set_switch "$sofcard" "$aec_sup" on

arecord -D "$WEBRTC_CAP_DEV" -f "$WEBRTC_CAP_FMT" -r "$WEBRTC_CAP_RATE" \
    -c "$WEBRTC_CAP_CH" -d 2 "${work_dir}/life_cap_only.wav" ||
    die "AEC capture-only failed"

aplay -D "$pb_ref_dev" -f "$WEBRTC_CAP_FMT" -r "$WEBRTC_CAP_RATE" \
    -c "$ref_ch" -d 2 /dev/zero ||
    die "AEC playback-only failed"

dyn_cap="${work_dir}/life_dynamic_ref.wav"
rm -f "$dyn_cap"
arecord -D "$WEBRTC_CAP_DEV" -f "$WEBRTC_CAP_FMT" -r "$WEBRTC_CAP_RATE" \
    -c "$WEBRTC_CAP_CH" -d 7 "$dyn_cap" &
dyn_cap_pid=$!
sleep 2
aplay -D "$pb_ref_dev" -f "$WEBRTC_CAP_FMT" -r "$WEBRTC_CAP_RATE" \
    -c "$ref_ch" -d 3 /dev/zero || {
    kill "$dyn_cap_pid" 2>/dev/null || true
    wait "$dyn_cap_pid" 2>/dev/null || true
    die "Dynamic mid-stream AEC ref playback failed"
}
wait "$dyn_cap_pid" || die "Dynamic mid-stream AEC capture failed"

sample_bytes=2
[ "$WEBRTC_CAP_FMT" = "S32_LE" ] && sample_bytes=4
min_bytes=$((WEBRTC_CAP_RATE * WEBRTC_CAP_CH * sample_bytes * 6))
actual_bytes=$(wc -c < "$dyn_cap")
[ "$actual_bytes" -ge "$min_bytes" ] ||
    die "Dynamic AEC capture stalled: got $actual_bytes bytes (< $min_bytes)"

# Phase 2: Echo cancellation DSP quality across configured echo delay(s)
mic_wav="${work_dir}/stim_aec_mic.wav"
ref_wav="${work_dir}/stim_aec_ref.wav"

run_aec_pass()
{
    local out_wav="$1"
    rm -f "$out_wav"
    arecord -D "$WEBRTC_CAP_DEV" -f "$WEBRTC_CAP_FMT" -r "$WEBRTC_CAP_RATE" \
        -c "$WEBRTC_CAP_CH" -d 7 "$out_wav" &
    local rec_pid=$!
    sleep 0.25

    aplay -D "$pb_ref_dev" "$ref_wav" &
    local ref_pid=$!

    local mic_rc=0
    case "$io_mode" in
        ssp)
            if [ "$pb_mic_dev" != "$pb_ref_dev" ]; then
                aplay -D "$pb_mic_dev" "$mic_wav" || mic_rc=$?
            fi
            ;;
        loopback)
            ;;
        usb)
            local resolved_usb
            resolved_usb=$(func_webrtc_detect_usb_pcm "$usb_pcm") || {
                kill "$ref_pid" "$rec_pid" 2>/dev/null || true
                wait "$ref_pid" "$rec_pid" 2>/dev/null || true
                skip_test "No USB audio device found (pass -U plughw:N,0)"
            }
            aplay -D "$resolved_usb" "$mic_wav" || mic_rc=$?
            ;;
        host)
            local cmd_tpl="${host_cmd:-${WEBRTC_HOST_PLAY_CMD:-}}"
            [ -n "$cmd_tpl" ] || {
                kill "$ref_pid" "$rec_pid" 2>/dev/null || true
                wait "$ref_pid" "$rec_pid" 2>/dev/null || true
                skip_test "Host mode requires -H '<cmd>' or WEBRTC_HOST_PLAY_CMD"
            }
            if [[ "$cmd_tpl" == *"{wav}"* ]]; then
                eval "${cmd_tpl//\{wav\}/\"$mic_wav\"}" || mic_rc=$?
            else
                eval "$cmd_tpl" < "$mic_wav" || mic_rc=$?
            fi
            ;;
        *)
            kill "$ref_pid" "$rec_pid" 2>/dev/null || true
            die "Unsupported io_mode '$io_mode'"
            ;;
    esac

    local ref_rc=0 rec_rc=0
    wait "$ref_pid" || ref_rc=$?
    wait "$rec_pid" || rec_rc=$?
    if [ "$mic_rc" -ne 0 ] || [ "$ref_rc" -ne 0 ] || [ "$rec_rc" -ne 0 ]; then
        die "AEC playback/capture stream failed (mic=$mic_rc ref=$ref_rc rec=$rec_rc)"
    fi
}

single_talk_flag=""
if [ "$io_mode" = "loopback" ] || { [ "$io_mode" = "ssp" ] && [ "$pb_mic_dev" = "$pb_ref_dev" ]; }; then
    single_talk_flag="--single-talk-only"
fi

IFS=',' read -ra echo_delays <<< "$delay_list"
for echo_delay_ms in "${echo_delays[@]}"; do
    # shellcheck disable=SC2086
    sof-webrtc-tool.py generate --profile aec --rate "$WEBRTC_CAP_RATE" \
        --mic-channels "$WEBRTC_CAP_CH" --ref-channels "$ref_ch" \
        --format "$WEBRTC_CAP_FMT" --echo-delay-ms "$echo_delay_ms" \
        $stereo_ind_flag --out-mic "$mic_wav" --out-ref "$ref_wav"

    for iter in $(seq 1 "$loop_cnt"); do
        dlogi "===== AEC Phase 2 delay=${echo_delay_ms}ms iter=${iter}/${loop_cnt} (mode=$io_mode mic=${WEBRTC_CAP_CH}ch ref=${ref_ch}ch) ====="
        off_wav="${work_dir}/cap_aec_off_d${echo_delay_ms}_${iter}.wav"
        on_wav="${work_dir}/cap_aec_on_d${echo_delay_ms}_${iter}.wav"

        if [ -n "$aec_sw" ]; then
            func_webrtc_set_switch "$sofcard" "$aec_sw" off
            [ -n "$aec_sup" ] && func_webrtc_set_switch "$sofcard" "$aec_sup" off
            run_aec_pass "$off_wav"

            func_webrtc_set_switch "$sofcard" "$aec_sw" on
            [ -n "$aec_sup" ] && func_webrtc_set_switch "$sofcard" "$aec_sup" on
            run_aec_pass "$on_wav"

            # shellcheck disable=SC2086
            sof-webrtc-tool.py analyze --profile aec --captured "$on_wav" \
                --baseline "$off_wav" $single_talk_flag $stereo_ind_flag ||
                die "WebRTC AEC A/B ERLE verification failed (delay=${echo_delay_ms}ms)"
        else
            run_aec_pass "$on_wav"
            # shellcheck disable=SC2086
            sof-webrtc-tool.py analyze --profile aec --captured "$on_wav" \
                $single_talk_flag $stereo_ind_flag ||
                die "WebRTC AEC verification failed (delay=${echo_delay_ms}ms)"
        fi
    done
done

sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
