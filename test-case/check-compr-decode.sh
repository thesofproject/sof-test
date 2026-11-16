#!/bin/bash

##
## Case Name: check-compr-decode
## Preconditions:
##    SOF topology with compressed playback pipeline (ffmpeg_dec)
## Description:
##    Validate compressed audio playback (decoding) across FFmpeg codecs
##    using cplay and/or sof-compr-tool.py, with optional pause/resume and
##    capture loopback verification.
## Case step:
##    1. Parse topology for type:playback & compress:1 pipelines
##    2. Generate compressed sine-wave test vectors via ffmpeg
##    3. Play each supported codec using cplay / sof-compr-tool.py
##    4. Check kernel logs for errors
## Expect result:
##    All tested decoders complete cleanly without kernel/DSP errors
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

OPT_NAME['m']='mode'            OPT_DESC['m']='player mode: auto, cplay, compr-tool, all'
OPT_HAS_ARG['m']=1              OPT_VAL['m']='auto'

OPT_NAME['d']='duration'        OPT_DESC['d']='test vector duration in seconds'
OPT_HAS_ARG['d']=1              OPT_VAL['d']=3

OPT_NAME['l']='loop'            OPT_DESC['l']='loop count per codec'
OPT_HAS_ARG['l']=1              OPT_VAL['l']=1

OPT_NAME['P']='pause_resume'    OPT_DESC['P']='pause/resume cycles during playback'
OPT_HAS_ARG['P']=1              OPT_VAL['P']=0

OPT_NAME['o']='output'          OPT_DESC['o']='working dir for generated vectors'
OPT_HAS_ARG['o']=1              OPT_VAL['o']="$LOG_ROOT/compr-decode"

OPT_NAME['L']='loopback_pcm'    OPT_DESC['L']='optional capture PCM (hw:C,D) for tone verify'
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
pause_cycles=${OPT_VAL['P']}
work_dir=${OPT_VAL['o']}
loopback_pcm=${OPT_VAL['L']}
filter_str=${OPT_VAL['S']}

start_test
logger_disabled || func_lib_start_log_collect
func_lib_check_sudo

if [ "$tool_mode" = "cplay" ] && ! func_compr_has_bin cplay; then
    skip_test "cplay binary not found in PATH"
fi

if [ "$tool_mode" = "cplay" ] && [ "$pause_cycles" -gt 0 ]; then
    die "Invalid combination: cplay mode does not support --pause_resume ($pause_cycles)"
fi

func_pipeline_export "$tplg" "type:playback & compress:1 & ${filter_str}"

mkdir -p "$work_dir"

if [ "$codec_opt" = "auto" ]; then
    codec_list="$COMPR_DECODE_CODECS_ALL"
else
    codec_list="${codec_opt//,/ }"
fi

tested_count=0
tone_hz=997

for idx in $(seq 0 $((PIPELINE_COUNT - 1))); do
    dev=$(func_pipeline_parse_value "$idx" dev)
    snd=$(func_pipeline_parse_value "$idx" snd)
    pcm=$(func_pipeline_parse_value "$idx" pcm)

    dlogi "Testing compress playback pipeline: $pcm [$dev] ($snd)"

    for codec in $codec_list; do
        caps_rc=0
        func_compr_dev_supports_codec "$snd" playback "$codec" || caps_rc=$?
        if [ "$caps_rc" -eq 1 ]; then
            dlogi "Skipping codec=$codec (not advertised in GET_CAPS on $snd)"
            continue
        elif [ "$caps_rc" -ne 0 ]; then
            die "Failed to query compress playback capabilities on $snd"
        fi

        modes_to_run=()
        case "$tool_mode" in
            cplay)
                func_compr_cplay_supports "$codec" || {
                    dlogi "Skipping codec=$codec (unsupported by cplay)"
                    continue
                }
                modes_to_run=(cplay)
                ;;
            compr-tool)
                modes_to_run=(compr-tool)
                ;;
            all)
                if [ "$pause_cycles" -eq 0 ] && func_compr_cplay_supports "$codec"; then
                    modes_to_run+=(cplay)
                elif [ "$pause_cycles" -gt 0 ] && func_compr_cplay_supports "$codec"; then
                    dlogi "Skipping mode=cplay for codec=$codec (pause/resume unsupported by cplay)"
                fi
                modes_to_run+=(compr-tool)
                ;;
            auto)
                modes_to_run=(auto)
                ;;
            *)
                die "Invalid mode: $tool_mode (expected auto|cplay|compr-tool|all)"
                ;;
        esac

        defaults=$(func_compr_codec_defaults "$codec")
        read -r rate ch _ _ _ _ <<< "$defaults"
        vec_file="${work_dir}/dec_${codec}_${rate}hz_${ch}ch_${duration}s.${codec}"
        if [ "$codec" = "alac" ]; then
            vec_file="${work_dir}/dec_alac_${rate}hz_${ch}ch_${duration}s.m4a"
        elif [ "$codec" = "msbc" ]; then
            vec_file="${work_dir}/dec_msbc_${rate}hz_${ch}ch_${duration}s.sbc"
        fi

        if [ ! -s "$vec_file" ]; then
            func_compr_gen_vector "$codec" "$vec_file" "$duration" "$tone_hz" || \
                die "Failed to generate $codec test vector"
        fi

        for mode in "${modes_to_run[@]}"; do
            for i in $(seq 1 "$loop_cnt"); do
                dlogi "===== Decode: $pcm ($snd) codec=$codec mode=$mode loop=$i/$loop_cnt ====="
                cap_pid=""
                cap_wav=""
                if [ -n "$loopback_pcm" ]; then
                    cap_wav="${work_dir}/loopback_${codec}_${mode}_${i}.wav"
                    arecord -D "$loopback_pcm" -f S16_LE -r 48000 -c 2 \
                        -d $((duration + 1)) -q "$cap_wav" &
                    cap_pid=$!
                    sleep 0.2
                fi

                if ! func_compr_run_play "$mode" "$snd" "$codec" "$vec_file" "$pause_cycles" "$duration"; then
                    if [ -n "$cap_pid" ]; then
                        kill "$cap_pid" 2>/dev/null || true
                    fi
                    func_lib_lsof_error_dump "$snd"
                    die "Decode playback failed: codec=$codec mode=$mode dev=$snd"
                fi

                if [ -n "$cap_pid" ]; then
                    wait "$cap_pid" || die "Loopback arecord failed on $loopback_pcm"
                    func_compr_verify_wav_tone "$cap_wav" "$tone_hz" || \
                        die "Loopback tone verification failed for $codec"
                fi
                tested_count=$((tested_count + 1))
            done
        done
    done
done

if [ "$tested_count" -eq 0 ]; then
    skip_test "No codecs matched device capabilities and selected mode ($tool_mode)"
fi

dlogi "Completed $tested_count compressed decode test runs"
sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
exit $?
