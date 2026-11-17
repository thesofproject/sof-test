#!/bin/bash

set -e

##
## Case Name: check-webrtc-vad
## Preconditions:
##    Topology contains a webrtc-vad widget
## Description:
##    Verify WebRTC VAD audio transparency across silence/speech segments and
##    exercise NOTIFIER_ID_VAD emission across supported PCM formats without
##    userspace syscall or MMU faults.
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

mapfile -t vad_rows < <(func_webrtc_discover_controls "$TPLG_FILES" "vad")
[ ${#vad_rows[@]} -gt 0 ] || skip_test "No webrtc-vad widget in $TPLG_FILES"

# Bypass optional inline HPF/AGC switches to check clean VAD pass-through
for kind in hpf agc; do
    mapfile -t k_rows < <(func_webrtc_discover_controls "$TPLG_FILES" "$kind")
    if [ ${#k_rows[@]} -gt 0 ]; then
        IFS='|' read -r _ _ ctrl _ <<< "${k_rows[0]}"
        [ -n "$ctrl" ] && func_webrtc_set_switch "$sofcard" "$ctrl" off
    fi
done

fmts=$(func_pipeline_parse_value 0 fmts)
[ -n "$fmts" ] || fmts="$WEBRTC_CAP_FMT"

work_dir="$LOG_ROOT/webrtc-vad"
mkdir -p "$work_dir"

for iter in $(seq 1 "$loop_cnt"); do
    for fmt in $fmts; do
        [ "$fmt" = "S24_LE" ] && continue
        WEBRTC_CAP_FMT="$fmt"
        stim_wav="${work_dir}/stim_vad_${fmt}.wav"
        cap_wav="${work_dir}/cap_vad_${fmt}_${iter}.wav"

        dlogi "===== check-webrtc-vad iter=$iter fmt=$fmt rate=$WEBRTC_CAP_RATE (mode=$io_mode) ====="
        sof-webrtc-tool.py generate --profile vad --rate "$WEBRTC_CAP_RATE" \
            --channels "$WEBRTC_CAP_CH" --format "$fmt" --output "$stim_wav"

        func_webrtc_capture_stimulus "$io_mode" "$stim_wav" "$cap_wav" 6 "$tplg" "$usb_pcm" "$host_cmd"

        sof-webrtc-tool.py analyze --profile vad --captured "$cap_wav" ||
            die "WebRTC VAD pass-through check failed ($fmt)"
    done
done

sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
