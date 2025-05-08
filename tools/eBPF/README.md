# Enhanced Berkeley Packet Filter (eBPF) scripts

bpftrace must be installed to be able to use eBPF scripts:

```
sudo apt install bpftrace
sudo dnf install bpftrace
sudo pacman -S bpftrace
sudo emerge -a bpftrace
...
```

**Note**: the distro provided bpftrace might be old, in that case the tool can be downloaded from [https://github.com/bpftrace/bpftrace/releases](URL)

## ipc4-msg-trace.bt

The script will tap onto the entry of sof_ipc4_log_header() to log IPC messages.
It will start logging the sent messages (including payloads) and received notification with exception of 0x1b060000 - trace update.

### To use the script:

```
sudo ./tools/sof-ipc4-msg-trace.bt
or
sudo bpftrace tools/sof-ipc4-msg-trace.bt
```

To stop the logging, just terminate the script with CTRL+C
