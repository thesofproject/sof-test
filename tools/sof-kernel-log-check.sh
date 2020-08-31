#!/bin/bash

begin_timestamp=${1:-0}
declare err_str ignore_str project_key
err_str="error|failed|timed out|panic|oops"

# TODO explain
# The first string cannot start by |
ignore_str='error: debugfs write failed to idle -16'

# Generic systemd error
# https://sof-ci.01.org/softestpr/PR354/build123/devicetest/
ignore_str="$ignore_str"'|systemd\[.*\]: Dependency failed .*'

# Generic initramfs error
# https://sof-ci.01.org/softestpr/PR354/build123/devicetest/
ignore_str="$ignore_str"'|Initramfs unpacking failed: Decoding failed'

# Generic ACPI errors
# https://sof-ci.01.org/softestpr/PR354/build123/devicetest/
ignore_str="$ignore_str"'|ACPI Error: Aborting method .* due to previous error'
ignore_str="$ignore_str"'|ACPI: \\: failed to evaluate .*'

# Generic sdhci-apci errors
# https://sof-ci.01.org/softestpr/PR354/build123/devicetest/
ignore_str="$ignore_str"'|sdhci-acpi 80860F16:00: failed to setup card detect gpio'

# Generic sdhci-pci errors
# https://sof-ci.01.org/softestpr/PR354/build123/devicetest/
ignore_str="$ignore_str"'|sdhci-pci 0000:00:..\.0: failed to setup card detect gpio'

# Generic ATA errors
# https://sof-ci.01.org/softestpr/PR354/build123/devicetest/
ignore_str="$ignore_str"'|ata3: COMRESET failed \(errno=-16\)'

# CML Helios known issue related with xhci_hcd
# https://bugzilla.kernel.org/show_bug.cgi?id=202541
ignore_str="$ignore_str"'|xhci_hcd 0000:00:14\.0: WARN Set TR Deq Ptr cmd failed due to incorrect slot or ep state'

# CML Helios / CML Mantis known issue related to MSR access
# https://sof-ci.01.org/softestpr/PR354/build136/devicetest/
ignore_str="$ignore_str"'|unchecked MSR access error: .*'

# CML Mantis occasionally throws Intel(R) Management Engine Interface(mei) errors
# https://unix.stackexchange.com/questions/109294/mei-00000016-0-init-hw-failure
ignore_str="$ignore_str"'|mei_me 0000:00:16\.0: wait hw ready failed'
ignore_str="$ignore_str"'|mei_me 0000:00:16\.0: hw_start failed ret = -62'

# CML Mantis has DELL touchpad i2c error on suspend/resume
ignore_str="$ignore_str"'|i2c_designware i2c_designware\.0: controller timed out'
ignore_str="$ignore_str"'|i2c_hid i2c-DELL0955:00: failed to change power setting'
ignore_str="$ignore_str"'|PM: Device i2c-DELL0955:00 failed to resume async: error -110'

# GLK i2c SRM failed to lock, found while running check-playback-all-formats.sh
# https://github.com/thesofproject/sof-test/issues/348
ignore_str="$ignore_str"'|da7219 i2c-DLGS7219:00: SRM failed to lock'

# Dell CML-U laptop with SoundWire, issues reported by sof-test
# https://github.com/thesofproject/sof-test/issues/343
ignore_str="$ignore_str"'|tpm tpm0: tpm_try_transmit: send\(\): error -5'
ignore_str="$ignore_str"'|platform regulatory\.0: Direct firmware load for regulatory\.db failed with error -2'
ignore_str="$ignore_str"'|cfg80211: failed to load regulatory\.db'
ignore_str="$ignore_str"'|EXT4-fs \(nvme0n1p6\): re-mounted\. Opts: errors=remount-ro'
ignore_str="$ignore_str"'|usb 2-3: Enable of device-initiated U1 failed\.'
ignore_str="$ignore_str"'|usb 2-3: Enable of device-initiated U2 failed\.'
ignore_str="$ignore_str"'|iwlwifi 0000:00:14\.3: Direct firmware load for iwlwifi-QuZ-a0-hr-b0-56\.ucode failed with error -2'
ignore_str="$ignore_str"'|iwlwifi 0000:00:14\.3: Direct firmware load for iwlwifi-QuZ-a0-hr-b0-55\.ucode failed with error -2'
ignore_str="$ignore_str"'|iwlwifi 0000:00:14\.3: Direct firmware load for iwlwifi-QuZ-a0-hr-b0-54\.ucode failed with error -2'
ignore_str="$ignore_str"'|iwlwifi 0000:00:14\.3: Direct firmware load for iwlwifi-QuZ-a0-hr-b0-53\.ucode failed with error -2'
ignore_str="$ignore_str"'|iwlwifi 0000:00:14\.3: Direct firmware load for iwlwifi-QuZ-a0-hr-b0-52\.ucode failed with error -2'
ignore_str="$ignore_str"'|iwlwifi 0000:00:14\.3: Direct firmware load for iwlwifi-QuZ-a0-hr-b0-51\.ucode failed with error -2'
ignore_str="$ignore_str"'|iwlwifi 0000:00:14\.3: Direct firmware load for iwlwifi-QuZ-a0-hr-b0-50\.ucode failed with error -2'
ignore_str="$ignore_str"'|iwlwifi 0000:00:14\.3: Direct firmware load for iwlwifi-QuZ-a0-hr-b0-49\.ucode failed with error -2'
ignore_str="$ignore_str"'|iwlwifi 0000:00:14\.3: Direct firmware load for iwl-debug-yoyo\.bin failed with error -2'
ignore_str="$ignore_str"'|thermal thermal_zone.*: failed to read out thermal zone \(-61\)'

# Dell CML-U laptop with SoundWire, issues reported by sof-test
# BugLink: https://github.com/thesofproject/sof-test/issues/307
ignore_str="$ignore_str"'|iwlwifi 0000:00:14\.3: Microcode SW error detected\. Restarting 0x0\.'
ignore_str="$ignore_str"'|wlo1: authentication with f4:f5:e8:6b:45:bb timed out'

[[ ! "$err_str" ]] && echo "Missing error keyword list" && exit 0

# confirm begin_timestamp is valid, if it is not the number, search full log
re='^[0-9]+$'
if [[ $begin_timestamp =~ $re ]] ; then
    cmd="journalctl -k"
else
    cmd="journalctl -k --since='$begin_timestamp'"
fi

# Handle warnings first
if [ "$ignore_str" ]; then
    err=$(eval $cmd --priority=warning | grep -E "$err_str" | grep -vE "$ignore_str")
else
    err=$(eval $cmd --priority=warning | grep -E "$err_str")
fi
if [ "$err" ]; then
    echo `date -u '+%Y-%m-%d %T %Z'` "[ERROR]" "Caught journalctl -k error"
    echo "===========================>>"
    echo "$err"
    echo "<<==========================="
    builtin exit 1
fi

# Handle Call Trace separately
err_trace=$(eval $cmd | grep 'Call Trace' -A5 -B3)
if [ "$err_trace" ]; then
    echo `date -u '+%Y-%m-%d %T %Z'` "[ERROR]" "Caught trace call"
    echo "===========================>>"
    echo "$err_trace"
    echo "<<==========================="
    builtin exit 1
fi

builtin exit 0
