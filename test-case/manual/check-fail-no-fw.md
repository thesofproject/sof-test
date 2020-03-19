# Missing expected SOF firmware test
The missing SOF firmware test is a regression test based on a sof_probe function failure documented in [linux#1762](https://github.com/thesofproject/linux/issues/1762) and is part of a series of manual tests associated with regression-linux1762-system-hand-when-sof-probe-fail.md

# Preconditions
PulseAudio should be enabled

# Test Description
* Check system does not hang when expected SOF firmware is missing by renaming the fw directory and letting sof_probe functions fail

## Test Case:
1. Rename fw directory, via `sudo mv /lib/firmware/intel/sof /lib/firmware/intel/sof_backup`
2. Reboot system -> System should not hang after bootup
3. Let system enter suspend & wakeup via `sudo rtcwake -m mem -s 10` -> System should not hang during or after suspend / resume cycle
4. Restore fw directory via `sudo mv /lib/firmware/intel/sof_backup /lib/firmware/intel/sof`
5. Reboot system -> SOF is loaded sucessfully
6. Repeat step 1 and step 3 without reboot system -> System should not hang during or after suspend / resume cycle
7. Repeat step 4 and step 5 to restore fw directory and reboot system -> SOF is loaded successfully

## Expected results
* System should not hang when expected SOF firmware is missing

