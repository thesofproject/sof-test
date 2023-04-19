#!/bin/bash
set -e

# Uses the function graph tracer to collect execution details for sof_io_read

main() {
    # Temporary, this puts logs in the dir of the hijacked script
    BASH_ARGV0=test-speaker.sh
    # shellcheck source=case-lib/lib.sh
    source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

    # Clear existing trace logs
    sudo bash -c "'echo > /sys/kernel/debug/tracing/trace'"
    # Setup tracing
    sudo bash -c "'echo > /sys/kernel/debug/tracing/set_ftrace_filter'"
    sudo bash -c "'echo sof_io_read > /sys/kernel/debug/tracing/set_graph_function'"
    sudo bash -c "'echo function_graph > /sys/kernel/debug/tracing/current_tracer'"
    sudo bash -c "'echo 1 > /sys/kernel/debug/tracing/tracing_on'"
    # Trigger `sof_io_read`s
    aplay -Dhw:0,0 -c2 -r48000 -c2 -fS16_LE -d 5 /dev/urandom
    # Save trace
    sudo cat /sys/kernel/debug/tracing/trace > "$LOG_ROOT/trace.txt"
    # Clear tracing config
    sudo bash -c "'echo > /sys/kernel/debug/tracing/current_tracer'"
    sudo bash -c "'echo > /sys/kernel/debug/tracing/set_graph_function'"
    sudo bash -c "'echo 0 > /sys/kernel/debug/tracing/tracing_on'"
}

main
