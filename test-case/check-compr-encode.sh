#!/bin/bash

##
## Case Name: check-compr-encode
## Preconditions:
##    SOF topology with compressed capture pipeline (ffmpeg_enc)
## Description:
##    Validate compressed audio capture (encoding) across FFmpeg codecs
##    using crecord and/or sof-compr-tool.py, verifying container/sync headers
##    and host ffmpeg decodability (plus optional playback loopback tone).
## Case step:
##    1. Parse topology for type:capture & compress:1 pipelines
##    2. Capture compressed audio stream for each supported codec
##    3. Verify encoded bitstream headers and decode via host ffmpeg
##    4. Check kernel logs for errors
## Expect result:
##    All tested encoders produce valid, decodable compressed streams
##

set -e

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh
# shellcheck source=case-lib/compress.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/compress.sh

OPT_NAME['t']='tplg'            OPT_DESC['t']='tplg file, default value is env TPLG'
OPT_HAS_ARG['t']=1              OPT_VAL['t']="$TPLG"

OPT_NAME['C']='codecs'          OPT_DESC['C']='comma/space separated codec list or auto'
OPT_HAS_ARG['C']=1              OPT_VAL['C']='auto'

OPT_NAME['m']='mode'            OPT_DESC['m']='recorder mode: auto, crecord, compr-tool, all'
OPT_HAS_ARG['m']=1              OPT_VAL['m']='auto'

OPT_NAME['d']='duration'        OPT_DESC['d']='capture duration in seconds'
OPT_HAS_ARG['d']=1              OPT_VAL['d']=3

OPT_NAME['l']='loop'            OPT_DESC['l']='loop count per codec'
OPT_HAS_ARG['l']=1              OPT_VAL['l']=1

OPT_NAME['o']='output'          OPT_DESC['o']='output directory for encoded streams'
OPT_HAS_ARG['o']=1              OPT_VAL['o']="$LOG_ROOT/compr-encode"

OPT_NAME['L']='playback_pcm'    OPT_DESC['L']='optional playback PCM (hw:C,D) for loopback tone'
OPT_HAS_ARG['L']=1              OPT_VAL['L']=''

OPT_NAME['S']='filter_string'   OPT_DESC['S']='pipeline filter expression'
OPT_HAS_ARG['S']=1              OPT_VAL['S']='id:any'

OPT_NAME['s']='sof-logger'      OPT_DESC['s']="Open sof-logger trace stored at $LOG_ROOT"
OPT_HAS_ARG['s']=0              OPT_VAL['s']=1

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
codec_opt=${OPT_VAL['C']}
tool_mode=${OPT_VAL['m']}
duration=${OPT_VAL['d']}
loop_cnt=${OPT_VAL['l']}
work_dir=${OPT_VAL['o']}
playback_pcm=${OPT_VAL['L']}
filter_str=${OPT_VAL['S']}

start_test
logger_disabled || func_lib_start_log_collect
func_lib_check_sudo

if [ "$tool_mode" = "crecord" ] && ! func_compr_has_bin crecord; then
    skip_test "crecord binary not found in PATH"
fi

func_pipeline_export "$tplg" "type:capture & compress:1 & ${filter_str}"

mkdir -p "$work_dir"

if [ "$codec_opt" = "auto" ]; then
    codec_list="$COMPR_ENCODE_CODECS_ALL"
else
    codec_list="${codec_opt//,/ }"
fi

tested_count=0
tone_hz=997
tone_wav=""

if [ -n "$playback_pcm" ]; then
    func_compr_has_bin ffmpeg || die "ffmpeg required to synthesize loopback tone WAV"
    tone_wav="${work_dir}/ref_tone_${tone_hz}hz.wav"
    ffmpeg -y -v error -f lavfi \
        -i "sine=frequency=${tone_hz}:sample_rate=48000:duration=$((duration + 2))" \
        -ac 2 -c:a pcm_s16le "$tone_wav"
fi

for idx in $(seq 0 $((PIPELINE_COUNT - 1))); do
    dev=$(func_pipeline_parse_value "$idx" dev)
    snd=$(func_pipeline_parse_value "$idx" snd)
    pcm=$(func_pipeline_parse_value "$idx" pcm)

    dlogi "Testing compress capture pipeline: $pcm [$dev] ($snd)"

    for codec in $codec_list; do
        caps_rc=0
        func_compr_dev_supports_codec "$snd" capture "$codec" || caps_rc=$?
        if [ "$caps_rc" -eq 1 ]; then
            dlogi "Skipping codec=$codec (not advertised in GET_CAPS on $snd)"
            continue
        elif [ "$caps_rc" -ne 0 ]; then
            die "Failed to query compress capture capabilities on $snd"
        fi

        modes_to_run=()
        case "$tool_mode" in
            crecord)
                func_compr_crecord_supports "$codec" || {
                    dlogi "Skipping codec=$codec (unsupported by crecord)"
                    continue
                }
                modes_to_run=(crecord)
                ;;
            compr-tool)
                modes_to_run=(compr-tool)
                ;;
            all)
                func_compr_crecord_supports "$codec" && modes_to_run+=(crecord)
                modes_to_run+=(compr-tool)
                ;;
            auto)
                modes_to_run=(auto)
                ;;
            *)
                die "Invalid mode: $tool_mode (expected auto|crecord|compr-tool|all)"
                ;;
        esac

        for mode in "${modes_to_run[@]}"; do
            for i in $(seq 1 "$loop_cnt"); do
                dlogi "===== Encode: $pcm ($snd) codec=$codec mode=$mode loop=$i/$loop_cnt ====="
                enc_file="${work_dir}/enc_${pcm// /_}_${codec}_${mode}_${i}.${codec}"
                dec_wav="${work_dir}/dec_${pcm// /_}_${codec}_${mode}_${i}.wav"
                play_pid=""

                if [ -n "$tone_wav" ]; then
                    aplay -D "$playback_pcm" -q "$tone_wav" &
                    play_pid=$!
                    sleep 0.2
                fi

                if ! func_compr_run_record "$mode" "$snd" "$codec" "$enc_file" "$duration"; then
                    if [ -n "$play_pid" ]; then
                        kill "$play_pid" 2>/dev/null || true
                    fi
                    func_lib_lsof_error_dump "$snd"
                    die "Encode capture failed: codec=$codec mode=$mode dev=$snd"
                fi

                if [ -n "$play_pid" ]; then
                    wait "$play_pid" || true
                fi

                rm -f "$dec_wav"
                verify_rc=0
                func_compr_verify_encoded_file "$codec" "$enc_file" "${tone_wav:+$dec_wav}" || verify_rc=$?
                if [ "$verify_rc" -ne 0 ] && [ "$verify_rc" -ne 2 ]; then
                    die "Encoded bitstream verification failed for $codec ($mode)"
                fi

                if [ -n "$tone_wav" ]; then
                    if [ "$verify_rc" -eq 2 ]; then
                        die "Loopback tone verification unsupported for raw header-only $codec stream"
                    fi
                    func_compr_verify_wav_tone "$dec_wav" "$tone_hz" || \
                        die "Loopback encoded tone check failed for $codec"
                fi
                tested_count=$((tested_count + 1))
            done
        done
    done
done

if [ "$tested_count" -eq 0 ]; then
    skip_test "No codecs matched capture capabilities and selected mode ($tool_mode)"
fi

dlogi "Completed $tested_count compressed encode test runs"
sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
exit $?
