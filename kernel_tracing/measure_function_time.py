#!/usr/bin/env python3
import subprocess
import argparse


def run_bpftrace(function_name):
    script = f"""
kprobe:{function_name} {{
  // Record time immediately to avoid it being affected by bpftrace script
  @nsecs = nsecs;
  if (@start != 0 ) {{
    printf("ERROR: overlapping function start/stop\\n");
    exit();
  }}
  @start = @nsecs;
}}

kretprobe:{function_name} {{
  @duration = nsecs - @start;
  if (@start != 0) {{
    @start = 0;
    @nsecs_hist = hist(@duration);
    @avg_nsecs = avg(@duration);
    @max_nsecs = max(@duration);
    @min_nsecs = min(@duration);
  }}
}}

END {{
  delete(@start);
  delete(@nsecs);
  delete(@duration);
}}
"""
    p = subprocess.Popen(["sudo", "bpftrace", "-e", script])
    try:
        p.wait()
    except KeyboardInterrupt:
        p.send_signal(subprocess.signal.SIGINT)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description="Track execution time of a function in the kernel using bpftrace")
    parser.add_argument(
        "function_name", help="Name of the function to track")
    run_bpftrace(parser.parse_args().function_name)
