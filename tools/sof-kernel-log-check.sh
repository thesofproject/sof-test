#!/bin/bash

begin_line=${1:-1}
declare err_str ignore_str

platform=$(sof-dump-status.py -p)

err_str="error|failed|timed out|panic|oops"

# TODO explain
# The first string cannot start by |
ignore_str='error: debugfs write failed to idle -16'

# CML Helios known issue related with xhci_hcd
# https://bugzilla.kernel.org/show_bug.cgi?id=202541
ignore_str="$ignore_str"'|xhci_hcd 0000:00:14\.0: WARN Set TR Deq Ptr cmd failed due to incorrect slot or ep state'

# CML Mantis occasionally throws Intel(R) Management Engine Interface(mei) errors
# https://unix.stackexchange.com/questions/109294/mei-00000016-0-init-hw-failure
ignore_str="$ignore_str"'|mei_me 0000:00:16\.0: wait hw ready failed'
ignore_str="$ignore_str"'|mei_me 0000:00:16\.0: hw_start failed ret = -62'

# CML Mantis has DELL touchpad i2c error on suspend/resume
ignore_str="$ignore_str"'|i2c_designware i2c_designware\.0: controller timed out'
ignore_str="$ignore_str"'|i2c_hid i2c-DELL0955:00: failed to change power setting'
ignore_str="$ignore_str"'|PM: Device i2c-DELL0955:00 failed to resume async: error -110'

# Dell CML HDA laptop, issues reported by sof-test
# https://github.com/thesofproject/sof-test/issues/396
ignore_str="$ignore_str"'|i2c_hid i2c-DELL0955:00: failed to set a report to device\.'

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
ignore_str="$ignore_str"'|: authentication with ..:..:..:..:..:.. timed out'

# I915, issues reported by sof-test
# BugLink: https://github.com/thesofproject/sof-test/issues/374
ignore_str="$ignore_str"'|i915 0000:00:02\.0: \[drm\] ERROR TC cold unblock failed'
ignore_str="$ignore_str"'|i915 0000:00:02\.0: \[drm\] ERROR TC cold block failed'
# CHT devices with USB hub, issues reported by sof-test
# BugLink: https://github.com/thesofproject/sof-test/issues/431
ignore_str="$ignore_str"'|hub 2-.: .'
ignore_str="$ignore_str"'|usb 2-.: .'

# Test cases on some platforms fail because the boot retry message:
#
#    sof-audio-pci 0000:00:1f.3: status = 0x00000000 panic = 0x00000000
#    ...
#    Attempting iteration 1 of Core En/ROM load...
#
# Despite the real boot failure the retry message is not at the error
# level until after the last try. However we still use kern.log for now
# and it has no log levels, so this may unfortunately hide this same
# message at the 'error' level until we switch to journalctl
# --priority. Hopefully other issues will cause the test to fail in that
# case.
#
# For now the codes seem to be 0x00000000 and affected platforms have
# PCI ID 1f.3. Before adding other values make sure you update the list
# of affected systems in bug 3395 below.
#
# Buglink: https://github.com/thesofproject/sof/issues/3395
case "$platform" in
    # Audio PCI ID on CML Mantis is [8086:9dc8], which is defined as CNL in linux kernel.
    # https://github.com/thesofproject/linux/blob/topic/sof-dev/sound/soc/sof/sof-pci-dev.c
    icl|cml|cnl)
        ignore_str="$ignore_str"'|sof-audio-pci 0000:00:1f\.3: status = 0x[0]{8} panic = 0x[0]{8}'
        # There will be debug logs at each failed initializaiton of DSP before Linux 5.9
        #   sof-audio-pci 0000:00:1f.3: error: cl_dsp_init: timeout HDA_DSP_SRAM_REG_ROM_STATUS read
        #   sof-audio-pci 0000:00:1f.3: error: status = 0x00000000 panic = 0x00000000
        #   sof-audio-pci 0000:00:1f.3: error: Error code=0xffffffff: FW status=0xffffffff
        #   sof-audio-pci 0000:00:1f.3: error: iteration 0 of Core En/ROM load failed: -110
        # We will reinit DSP if it is failed to init, and retry 3 times, so the errors in
        # debug logs at the frist and second retry can be ignored.
        # Check https://github.com/thesofproject/linux/pull/1676 for more information.
        # Fixed by https://github.com/thesofproject/linux/pull/2382
        ignore_str="$ignore_str"'|error: iteration [01]'
        ignore_str="$ignore_str"'|error: status'
        ignore_str="$ignore_str"'|error: cl_dsp_init: timeout HDA_DSP_SRAM_REG_ROM_STATUS read'

        # On CML_RVP_SDW, suspend-resume test case failed due to "mei_me 0000:00:16.4: hw_reset failed ret = -62".
        # https://github.com/thesofproject/sof-test/issues/389
        ignore_str="$ignore_str"'|mei_me 0000:00:16\..: hw_reset failed ret = -62'
        ;;
esac

[[ ! "$err_str" ]] && echo "Missing error keyword list" && exit 0
# dmesg KB size buffer size
#dmesg_config_define=$(awk -F '=' '/CONFIG_LOG_BUF_SHIFT/ {print $2;}' /boot/config-$(uname -r))
#dmesg_buffer_size=$( echo $(( (1<<$dmesg_config_define) / 1024 )) )
# kernel file log buffer size
#kernel_buffer_size=$(du -k /var/log/kern.log |awk '{print $1;}')
# now decide using which to catch the kernel log
#[[ $kernel_buffer_size -lt $dmesg ]] && cmd="dmesg" || cmd="tail -n  +${begin_line}  /var/log/kern.log"

# confirm begin_line is number, if it is not the number, direct using dmesg
[[ "${begin_line//[0-9]/}" ]] && begin_line=0
[[ "$begin_line" -eq 0 ]] && cmd="dmesg" || cmd="tail -n  +${begin_line}  /var/log/kern.log"

#echo "run $0 with parameter '$*' for check kernel message error"

# declare -p cmd
if [ "$ignore_str" ]; then
    err=$(   $cmd | grep 'Call Trace' -A5 -B3)$(     $cmd | grep -E "$err_str"|grep -vE "$ignore_str")
else
    err=$(   $cmd | grep 'Call Trace' -A5 -B3)$(     $cmd | grep -E "$err_str")
fi

if [ "$err" ]; then
    echo "$(date -u '+%Y-%m-%d %T %Z')" "[ERROR]" "Caught dmesg error"
    echo "===========================>>"
    echo "$err"
    echo "<<==========================="
    builtin exit 1
fi
