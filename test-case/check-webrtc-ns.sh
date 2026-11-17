#!/bin/bash

set -e

##
## Case Name: check-webrtc-ns
## Preconditions:
##    Topology contains a webrtc-ns or webrtc-ns2 widget
## Description:
##    Verify WebRTC NS (16 kHz) / NS2 RNNoise (48 kHz) attenuates stationary
##    noise after convergence while preserving speech-band multitone SNR.
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

ns_profile=""
mapfile -t ns2_rows < <(func_webrtc_discover_controls "$TPLG_FILES" "ns2")
if [ ${#ns2_rows[@]} -gt 0 ]; then
    ns_profile="ns2"
else
    mapfile -t ns_rows < <(func_webrtc_discover_controls "$TPLG_FILES" "ns")
    if [ ${#ns_rows[@]} -gt 0 ]; then
        ns_profile="ns"
    fi
fi
[ -n "$ns_profile" ] || skip_test "No webrtc-ns or webrtc-ns2 widget in $TPLG_FILES"

# Keep HPF on (removes sub-80Hz bias) and AGC off so NS noise reduction isn't re-amplified
mapfile -t hpf_rows < <(func_webrtc_discover_controls "$TPLG_FILES" "hpf")
if [ ${#hpf_rows[@]} -gt 0 ]; then
    IFS='|' read -r _ _ hpf_ctrl _ <<< "${hpf_rows[0]}"
    [ -n "$hpf_ctrl" ] && func_webrtc_set_switch "$sofcard" "$hpf_ctrl" on
fi
mapfile -t agc_rows < <(func_webrtc_discover_controls "$TPLG_FILES" "agc")
if [ ${#agc_rows[@]} -gt 0 ]; then
    IFS='|' read -r _ _ agc_ctrl _ <<< "${agc_rows[0]}"
    [ -n "$agc_ctrl" ] && func_webrtc_set_switch "$sofcard" "$agc_ctrl" off
fi

work_dir="$LOG_ROOT/webrtc-${ns_profile}"
mkdir -p "$work_dir"
stim_wav="${work_dir}/stim_${ns_profile}.wav"
sof-webrtc-tool.py generate --profile "$ns_profile" --rate "$WEBRTC_CAP_RATE" \
    --channels "$WEBRTC_CAP_CH" --format "$WEBRTC_CAP_FMT" --output "$stim_wav"

for iter in $(seq 1 "$loop_cnt"); do
    dlogi "===== check-webrtc-ns ($ns_profile) iteration $iter/$loop_cnt (mode=$io_mode) ====="
    cap_wav="${work_dir}/cap_${ns_profile}_${iter}.wav"
    func_webrtc_capture_stimulus "$io_mode" "$stim_wav" "$cap_wav" 6 "$tplg" "$usb_pcm" "$host_cmd"

    sof-webrtc-tool.py analyze --profile "$ns_profile" --captured "$cap_wav" ||
        die "WebRTC $ns_profile noise suppression check failed"
done

sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
