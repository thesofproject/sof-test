#!/usr/bin/env python3

"""Module to stress test firmware boot"""

import argparse
import logging
import sys
from datetime import datetime
from systemd import journal

logging.basicConfig(level=logging.INFO, format="%(message)s")

# set path to the depbugfs entries
DEBUGFS_PATH = "/sys/kernel/debug/sof/fw_debug_ops"

def read_jctl_logs(start_time):
    """Reads journalctl logs from a given start time and extracts the timestamp and log"""
    journal_reader = journal.Reader()
    journal_reader.this_boot()
    journal_reader.seek_realtime(datetime.strptime(start_time, '%Y-%m-%d %H:%M:%S'))

    entries = []
    for entry in journal_reader:
        timestamp = entry['__REALTIME_TIMESTAMP']
        message = entry.get('MESSAGE', '')
        if isinstance(message, bytes):
            message = message.decode('utf-8', errors='replace')
        entries.append((timestamp, message))

    return entries

# define command line arguments
def parse_cmdline():
    """Function to parse the command line arguments"""
    parser = argparse.ArgumentParser(
        add_help=True,
        formatter_class=argparse.RawTextHelpFormatter,
        description="A script for stress testing firmware boot",
    )
    parser.add_argument(
        "-i", "--iter", type=int, default=100, help="number of firmware boot iterations"
    )
    parser.add_argument(
        "-f", "--firmware", type=str,
        help="firmware filename. If this is not set, the kernel will boot the default firmware"
    )
    parser.add_argument(
        "-p",
        "--fw_path",
        type=str,
        help="""path to the firmware file. If the path is not relative to /lib/firmware,
             use echo -n /path/to/fw_file > /sys/module/firmware_class/parameters/path""",
    )
    return parser.parse_args()

def dsp_set(node, value):
    """Set the debugfs node"""
    open(f"{DEBUGFS_PATH}/{node}", "w").write(f"{value}\n")

def dsp_get(node):
    """Get the value from a debugfs node"""
    return open(f"{DEBUGFS_PATH}/{node}").read().rstrip()

def boot_fw():
    """Power down the DSP and boot firmware using previously set firmware path and filename"""
    # put the DSP in D3
    dsp_set("dsp_power_state", "D3")

    # check if the DSP is in D3
    power_state = dsp_get("dsp_power_state")
    if power_state != "D3":
        sys.exit("Failed booting firmware. DSP is not in D3")

    # unload current firmware
    dsp_set("unload_fw", "1")

    # get current fw_state and continue to boot only if the current state is 'PREPARE'
    fw_state = dsp_get("fw_state")
    if "PREPARE" not in fw_state:
        sys.exit(f"Cannot boot firmware from current state {fw_state}")

    # load and boot firmware
    dsp_set("boot_fw", "1")

    # get current fw_state
    fw_state = dsp_get("fw_state")

    return fw_state

def calculate_boot_time(journalctl_output):
    """Calculate boot time from the journal ctl log entries"""
    boot_start_time = 0
    boot_end_time = 0
    for timestamp, message in journalctl_output:
        if 'booting DSP firmware' in message:
            boot_start_time = timestamp
        if 'firmware boot complete' in message:
            boot_end_time = timestamp
    if boot_start_time == 0 or boot_end_time == 0:
        sys.exit("Failed to calculate boot time")
    time_diff = boot_end_time - boot_start_time
    boot_time_ms = round(time_diff.total_seconds() * 1000, 2)

    return boot_time_ms

def main():
    """Main function for stress testing"""
    cmd_args = parse_cmdline()

   # clear firmware filename/path
    dsp_set("fw_filename", "")
    dsp_set("fw_path", "")

    # Get firmware file path if set
    if cmd_args.fw_path:
        fw_path = cmd_args.fw_path
        dsp_set("fw_path", fw_path)
    else:
        fw_path = "default"

    # Get firmware file name if set
    if cmd_args.firmware:
        fw_filename = cmd_args.firmware
        dsp_set("fw_filename", fw_filename)
    else:
        fw_filename = "default"

    num_iter = cmd_args.iter
    output = f"""==============================================================================
	Starting boot stress test with:
	Firmware filename: {fw_filename}
	Path to firmware file: {fw_path}
	Number of Iterations: {num_iter}
=============================================================================="""
    logging.info(output)

    total_boot_time_ms = 0
    min_boot_time_ms = sys.maxsize
    max_boot_time_ms = 0

    for i in range(num_iter):
        start_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        fw_state = boot_fw()
        # check if fw_state is COMPLETE
        if "COMPLETE" not in fw_state:
            sys.exit(f"Firmware boot failed at iteration {i}")

        journalctl_output = read_jctl_logs(start_time)

        boot_time_ms = calculate_boot_time(journalctl_output)
        total_boot_time_ms += boot_time_ms
        min_boot_time_ms = min(min_boot_time_ms, boot_time_ms)
        max_boot_time_ms = max(max_boot_time_ms, boot_time_ms)

        logging.info("Firmware boot iteration %d completed in %0.2f ms", i, boot_time_ms)

    # print firmware boot stats
    avg_boot_time_ms = round(total_boot_time_ms / num_iter, 2)
    output = f"""==============================================================================
	Average firmware boot time {avg_boot_time_ms} ms
	Maximum firmware boot time {max_boot_time_ms} ms
	Minimum firmware boot time {min_boot_time_ms} ms
=============================================================================="""
    logging.info(output)

if __name__ == "__main__":
    main()
