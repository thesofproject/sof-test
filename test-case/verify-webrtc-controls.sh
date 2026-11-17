#!/bin/bash

set -e

##
## Case Name: verify-webrtc-controls
## Preconditions:
##    SOF topology contains one or more WebRTC effect widgets
## Description:
##    Validate WebRTC widget presence, Switch kcontrol read/write toggling
##    during active PCM streaming, and clean LLEXT load without kernel errors.
##

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh
# shellcheck source=case-lib/webrtc.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/webrtc.sh

OPT_NAME['t']='tplg'       OPT_DESC['t']="tplg file, default value is env TPLG"
OPT_HAS_ARG['t']=1           OPT_VAL['t']="$TPLG"
OPT_NAME['l']='loop'       OPT_DESC['l']='toggle loop count'
OPT_HAS_ARG['l']=1           OPT_VAL['l']=2
OPT_NAME['s']='sof-logger' OPT_DESC['s']="Open sof-logger trace stored at $LOG_ROOT"
OPT_HAS_ARG['s']=0           OPT_VAL['s']=1

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
loop_cnt=${OPT_VAL['l']}

start_test
func_webrtc_register_cleanup
logger_disabled || func_lib_start_log_collect

func_webrtc_select_capture_pipeline "$tplg" "type:capture"
sofcard="${SOFCARD:-0}"

mapfile -t ctrl_rows < <(func_webrtc_discover_controls "$TPLG_FILES" "all")
[ ${#ctrl_rows[@]} -gt 0 ] || skip_test "No WebRTC widgets found in topology $TPLG_FILES"

declare -a switch_ctrls=()
for row in "${ctrl_rows[@]}"; do
    IFS='|' read -r mod_type wname kname ktype <<< "$row"
    dlogi "Discovered WebRTC widget: type=${mod_type} widget=${wname} ctrl='${kname}' (${ktype})"
    if [ -n "$kname" ] && { [ "$ktype" = "MIXER" ] || [ -z "$ktype" ]; }; then
        switch_ctrls+=("$kname")
    fi
done

# Start background capture so DSP loads WebRTC pipeline/LLEXT while toggling
dlogc "arecord -D $WEBRTC_CAP_DEV -f $WEBRTC_CAP_FMT -r $WEBRTC_CAP_RATE -c $WEBRTC_CAP_CH -d $((loop_cnt * 2 + 2)) /dev/null"
arecord -D "$WEBRTC_CAP_DEV" -f "$WEBRTC_CAP_FMT" -r "$WEBRTC_CAP_RATE" \
    -c "$WEBRTC_CAP_CH" -d "$((loop_cnt * 2 + 2))" /dev/null &
cap_pid=$!
sleep 1

for iter in $(seq 1 "$loop_cnt"); do
    dlogi "===== Control toggle iteration $iter/$loop_cnt ====="
    for ctrl in "${switch_ctrls[@]}"; do
        func_webrtc_set_switch "$sofcard" "$ctrl" off
        func_webrtc_set_switch "$sofcard" "$ctrl" on
        func_webrtc_set_switch "$sofcard" "$ctrl" off
    done
    sleep 1
done

wait "$cap_pid" || die "Capture stream failed during WebRTC control verification"
sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
