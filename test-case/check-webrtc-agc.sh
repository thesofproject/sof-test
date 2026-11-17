#!/bin/bash

set -e

##
## Case Name: check-webrtc-agc
## Preconditions:
##    Topology contains a webrtc-agc widget and AGC Switch mixer control
## Description:
##    Verify WebRTC digital AGC boosts quiet signals and limits near-full-scale
##    signals without digital clipping (Switch ON vs OFF A/B).
##

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh
# shellcheck source=case-lib/webrtc.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/webrtc.sh

OPT_NAME['t']='tplg'       OPT_DESC['t']="tplg file, default value is env TPLG"
OPT_HAS_ARG['t']=1           OPT_VAL['t']="$TPLG"
OPT_NAME['m']='io-mode'    OPT_DESC['m']='Audio injection mode: ssp | usb | host'
OPT_HAS_ARG['m']=1           OPT_VAL['m']='ssp'
OPT_NAME['U']='usb-pcm'    OPT_DESC['U']='USB ALSA PCM (for -m usb)'
OPT_HAS_ARG['U']=1           OPT_VAL['U']=''
OPT_NAME['H']='host-cmd'   OPT_DESC['H']='Host play command (for -m host)'
OPT_HAS_ARG['H']=1           OPT_VAL['H']=''
OPT_NAME['l']='loop'       OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1           OPT_VAL['l']=1
OPT_NAME['s']='sof-logger' OPT_DESC['s']="Open sof-logger trace stored at $LOG_ROOT"
OPT_HAS_ARG['s']=0           OPT_VAL['s']=1

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
io_mode=${OPT_VAL['m']}
usb_pcm=${OPT_VAL['U']}
host_cmd=${OPT_VAL['H']}
loop_cnt=${OPT_VAL['l']}

start_test
func_webrtc_register_cleanup
logger_disabled || func_lib_start_log_collect

func_webrtc_select_capture_pipeline "$tplg" "type:capture"
sofcard="${SOFCARD:-0}"

mapfile -t agc_rows < <(func_webrtc_discover_controls "$TPLG_FILES" "agc")
[ ${#agc_rows[@]} -gt 0 ] || skip_test "No webrtc-agc widget in $TPLG_FILES"
IFS='|' read -r _ _ agc_ctrl _ <<< "${agc_rows[0]}"
[ -n "$agc_ctrl" ] || skip_test "No AGC Switch control found in $TPLG_FILES"

work_dir="$LOG_ROOT/webrtc-agc"
mkdir -p "$work_dir"
stim_wav="${work_dir}/stim_agc.wav"
sof-webrtc-tool.py generate --profile agc --rate "$WEBRTC_CAP_RATE" \
    --channels "$WEBRTC_CAP_CH" --format "$WEBRTC_CAP_FMT" --output "$stim_wav"

for iter in $(seq 1 "$loop_cnt"); do
    dlogi "===== check-webrtc-agc iteration $iter/$loop_cnt (mode=$io_mode) ====="
    off_wav="${work_dir}/cap_agc_off_${iter}.wav"
    on_wav="${work_dir}/cap_agc_on_${iter}.wav"

    func_webrtc_set_switch "$sofcard" "$agc_ctrl" off
    func_webrtc_capture_stimulus "$io_mode" "$stim_wav" "$off_wav" 6 "$tplg" "$usb_pcm" "$host_cmd"

    func_webrtc_set_switch "$sofcard" "$agc_ctrl" on
    func_webrtc_capture_stimulus "$io_mode" "$stim_wav" "$on_wav" 6 "$tplg" "$usb_pcm" "$host_cmd"

    sof-webrtc-tool.py analyze --profile agc --captured "$on_wav" --baseline "$off_wav" ||
        die "WebRTC AGC verification failed"
done

sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
