#!/bin/bash

##
## Case Name: check-capture
## Preconditions:
##    N/A
## Description:
##    run arecord on each pipeline
##    default duration is 10s
##    default loop count is 3
## Case step:
##    1. Parse TPLG file to get pipeline with type of "record"
##    2. Specify the audio parameters
##    3. Run arecord on each pipeline with parameters
## Expect result:
##    The return value of arecord is 0
##

set -e

# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file, default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1         OPT_VAL['t']="$TPLG"

OPT_NAME['r']='round'     OPT_DESC['r']='round count'
OPT_HAS_ARG['r']=1         OPT_VAL['r']=1

OPT_NAME['d']='duration' OPT_DESC['d']='arecord duration in second'
OPT_HAS_ARG['d']=1         OPT_VAL['d']=10

OPT_NAME['l']='loop'     OPT_DESC['l']='loop count'
OPT_HAS_ARG['l']=1         OPT_VAL['l']=3

OPT_NAME['o']='output'   OPT_DESC['o']='output dir'
OPT_HAS_ARG['o']=1         OPT_VAL['o']="$LOG_ROOT/wavs"

OPT_NAME['f']='file'   OPT_DESC['f']='file name prefix'
OPT_HAS_ARG['f']=1         OPT_VAL['f']=''

OPT_NAME['s']='sof-logger'   OPT_DESC['s']="Open sof-logger trace the data will store at $LOG_ROOT"
OPT_HAS_ARG['s']=0             OPT_VAL['s']=1

OPT_NAME['F']='fmts'   OPT_DESC['F']='Iterate all supported formats'
OPT_HAS_ARG['F']=0         OPT_VAL['F']=0

OPT_NAME['S']='filter_string'   OPT_DESC['S']="run this case on specified pipelines"
OPT_HAS_ARG['S']=1             OPT_VAL['S']="id:any"

OPT_NAME['R']='samplerate'   OPT_DESC['R']='sample rate'
OPT_HAS_ARG['R']=1         OPT_VAL['R']=48000  # Default sample rate

OPT_NAME['T']='tplg_filename'   OPT_DESC['T']='new topology filename'
OPT_HAS_ARG['T']=1         OPT_VAL['T']=''  # Default empty

func_opt_parse_option "$@"

tplg=${OPT_VAL['t']}
round_cnt=${OPT_VAL['r']}
duration=${OPT_VAL['d']}
loop_cnt=${OPT_VAL['l']}
out_dir=${OPT_VAL['o']}
file_prefix=${OPT_VAL['f']}
samplerate=${OPT_VAL['R']}  # Use the sample rate specified by the -R option
new_tplg_filename=${OPT_VAL['T']}  # New topology filename
modprobe_file="/etc/modprobe.d/tplg_filename.conf"

script_name=$(basename "${BASH_SOURCE[0]}")

reboot_file="/var/tmp/$script_name/rebooted"

# Function to check and update topology filename, reload drivers, and confirm update
update_topology_filename() {
    if [[ -f "$modprobe_file" ]]; then
        old_topology=$(sudo cat "$modprobe_file")
        echo "Old topology: $old_topology"
    fi

    # Confirm current topology
    tplg_file=$(sudo journalctl -q -k | grep -i 'loading topology' | awk -F: '{ topo=$NF; } END { print topo }')
    echo "Current topology loaded: $tplg_file"

    if [[ -n "$new_tplg_filename" ]]; then
        echo "options snd-sof-pci tplg_filename=$new_tplg_filename" | sudo tee "$modprobe_file" > /dev/null
        echo "Updated topology filename to: $new_tplg_filename"

        # Reload drivers
        sudo sof-test/tools/kmod/sof_remove.sh
        sleep 5
        sudo sof-test/tools/kmod/sof_insert.sh
        sleep 5

        # Confirm updated topology
        tplg_file=$(sudo journalctl -q -k | grep -i 'loading topology' | awk -F: '{ topo=$NF; } END { print topo }')
        echo "Updated topology loaded: $tplg_file"
    fi
}

# Restore the original topology after the test
restore_topology() {
    if [[ -n "$old_topology" ]]; then
        # sleep 10
        echo "$old_topology" | sudo tee "$modprobe_file" > /dev/null
        echo "Restored original topology: $old_topology"
        # reboot_wrapper
        #Reload drivers to apply the original topology
        # sleep 5
        # sudo sof-test/tools/kmod/sof_remove.sh
        # sleep 5
        # sudo sof-test/tools/kmod/sof_insert.sh
        # sleep 5

        # Confirm restored topology
        # tplg_file=$(sudo journalctl -q -k | grep -i 'loading topology' | awk -F: '{ topo=$NF; } END { print topo }')
        # echo "Restored topology loaded: $tplg_file"
    fi
}

# Update topology filename if -T option is used
update_topology_filename
start_test
if [ ! -f "$reboot_file" ]; then
    logger_disabled || func_lib_start_log_collect
fi

setup_kernel_check_point

if [ -f $reboot_file ]; then
    dlogi "System rebooted"
    rm "$reboot_file"
    sof-kernel-log-check.sh "$KERNEL_CHECKPOINT"
    exit $?
fi

func_lib_check_sudo
func_pipeline_export "$tplg" "type:capture & ${OPT_VAL['S']}"

for round in $(seq 1 "$round_cnt")
do
    for idx in $(seq 0 $((PIPELINE_COUNT - 1)))
    do

        initialize_audio_params "$idx"

        if [ "${OPT_VAL['F']}" = '1' ]; then
            fmts=$(func_pipeline_parse_value "$idx" fmts)
        fi

        for fmt_elem in $fmts
        do
            for i in $(seq 1 "$loop_cnt")
            do
                dlogi "===== Testing: (Round: $round/$round_cnt) (PCM: $pcm [$dev]<$type>) (Loop: $i/$loop_cnt) ====="
                # get the output file
                if [[ -z $file_prefix ]]; then
                    dlogi "no file prefix, use /dev/null as dummy capture output"
                    file=/dev/null
                else
                    mkdir -p "$out_dir"
                    file=$out_dir/${file_prefix}_${dev}_${i}.wav
                    dlogi "using $file as capture output"
                fi

                # Ensure the sample rate is set correctly
                if ! arecord_opts -D"$dev" -r "$samplerate" -c "$channel" -f "$fmt_elem" -d "$duration" "$file" -v -q;
                then
                    func_lib_lsof_error_dump "$snd"
                    echo "arecord on PCM $dev failed at $i/$loop_cnt."
                    die "arecord on PCM $dev failed at $i/$loop_cnt."
                fi
            done
        done
    done
done

echo "Wait for remove"
#sleep 1000
restore_topology
mkdir -p "/var/tmp/$script_name"
touch "$reboot_file"
reboot_wrapper