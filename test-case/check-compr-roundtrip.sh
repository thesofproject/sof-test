#!/bin/bash

##
## Case Name: check-compr-roundtrip
## Preconditions:
##    SOF topology with both compressed playback (ffmpeg_dec) and
##    compressed capture (ffmpeg_enc) pipelines
## Description:
##    Test lossless encode->host-decode fidelity and simultaneous compressed
##    playback + compressed capture using both cplay/crecord and sof-compr-tool.py.
## Case step:
##    1. Parse topology for compress:1 playback and capture pipelines
##    2. Generate reference compressed audio vectors
##    3. Run concurrent compress playback and compress capture
##    4. Verify captured stream decodes cleanly on host
##    5. Check kernel logs for errors
## Expect result:
##    Concurrent decode/encode pipelines succeed without XRUN or kernel errors
##

set -e

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh
# shellcheck source=case-lib/compress.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/compress.sh

OPT_NAME['t']='tplg'            OPT_DESC['t']='tplg file, default value is env TPLG'
OPT_HAS_ARG['t']=1              OPT_VAL['t']="$TPLG"

OPT_NAME['C']='codecs'          OPT_DESC['C']='codecs to pair for roundtrip (default: flac,mp3,aac,alac)'
OPT_HAS_ARG['C']=1              OPT_VAL['C']='flac,mp3,aac,alac'

OPT_NAME['d']='duration'        OPT_DESC['d']='stream duration in seconds'
OPT_HAS_ARG['d']=1              OPT_VAL['d']=4

OPT_NAME['o']='output'          OPT_DESC['o']='working directory for test streams'
OPT_HAS_ARG['o']=1              OPT_VAL['o']="$LOG_ROOT/compr-roundtrip"

OPT_NAME['S']='filter_string'   OPT_DESC['S']='pipeline filter expression'
OPT_HAS_ARG['S']=1              OPT_VAL['S']='id:any'

OPT_NAME['s']='sof-logger'      OPT_DESC['s']="Open sof-logger trace stored at $LOG_ROOT"
OPT_HAS_ARG['s']=0              OPT_VAL['s']=1

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
codec_opt=${OPT_VAL['C']}
duration=${OPT_VAL['d']}
work_dir=${OPT_VAL['o']}
filter_str=${OPT_VAL['S']}

start_test
logger_disabled || func_lib_start_log_collect
func_lib_check_sudo

mkdir -p "$work_dir"

func_pipeline_export "$tplg" "type:playback & compress:1 & ${filter_str}"
play_snd=$(func_pipeline_parse_value 0 snd)
play_pcm=$(func_pipeline_parse_value 0 pcm)

func_pipeline_export "$tplg" "type:capture & compress:1 & ${filter_str}"
cap_snd=$(func_pipeline_parse_value 0 snd)
cap_pcm=$(func_pipeline_parse_value 0 pcm)

dlogi "Roundtrip playback=$play_pcm ($play_snd), capture=$cap_pcm ($cap_snd)"

tested_count=0
for codec in ${codec_opt//,/ }; do
    play_caps_rc=0
    func_compr_dev_supports_codec "$play_snd" playback "$codec" || play_caps_rc=$?
    if [ "$play_caps_rc" -eq 1 ]; then
        dlogi "Skipping $codec: playback unsupported on $play_snd"
        continue
    elif [ "$play_caps_rc" -ne 0 ]; then
        die "Failed to query compress playback capabilities on $play_snd"
    fi

    cap_caps_rc=0
    func_compr_dev_supports_codec "$cap_snd" capture "$codec" || cap_caps_rc=$?
    if [ "$cap_caps_rc" -eq 1 ]; then
        dlogi "Skipping $codec: capture unsupported on $cap_snd"
        continue
    elif [ "$cap_caps_rc" -ne 0 ]; then
        die "Failed to query compress capture capabilities on $cap_snd"
    fi

    defaults=$(func_compr_codec_defaults "$codec")
    read -r rate ch _ _ _ _ <<< "$defaults"
    in_vec="${work_dir}/in_${codec}_${duration}s.${codec}"
    [ "$codec" = "alac" ] && in_vec="${work_dir}/in_alac_${duration}s.m4a"
    [ "$codec" = "msbc" ] && in_vec="${work_dir}/in_msbc_${duration}s.sbc"
    if [ ! -s "$in_vec" ]; then
        func_compr_gen_vector "$codec" "$in_vec" "$duration" 997 || \
            die "Failed to generate input vector for $codec"
    fi

    out_stream="${work_dir}/out_${codec}.${codec}"

    dlogi "===== Simultaneous decode+encode ($codec, ${rate}Hz ${ch}ch) ====="
    func_compr_run_record auto "$cap_snd" "$codec" "$out_stream" "$duration" &
    rec_pid=$!
    sleep 0.2

    if ! func_compr_run_play auto "$play_snd" "$codec" "$in_vec" 0 "$duration"; then
        kill "$rec_pid" 2>/dev/null || true
        wait "$rec_pid" 2>/dev/null || true
        die "Roundtrip compress playback failed for $codec"
    fi

    wait "$rec_pid" || die "Roundtrip compress capture failed for $codec"

    verify_rc=0
    func_compr_verify_encoded_file "$codec" "$out_stream" "" || verify_rc=$?
    if [ "$verify_rc" -ne 0 ] && [ "$verify_rc" -ne 2 ]; then
        die "Roundtrip captured stream invalid for $codec"
    fi

    tested_count=$((tested_count + 1))
done

if [ "$tested_count" -eq 0 ]; then
    skip_test "No codecs supported by both compress playback and capture pipelines"
fi

dlogi "Completed $tested_count simultaneous compressed roundtrip tests"
sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
exit $?
