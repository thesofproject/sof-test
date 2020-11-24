#!/bin/bash

# This file is a (crude) database of well-known error messages that we
# don't want to be reported as failures for various reasons.
#
# It is the equivalent of the (tightly controlled) passlist in this
# file:
# https://gitlab.freedesktop.org/drm/igt-gpu-tools/-/blob/64f3a4c4351/runner/resultgen.c#L776
#
# Ignoring errors is very dangerous for reasons detailed below so please
# read this and think twice before making changes in this file.

# Error types
# -----------
#
# This "database" gathers different sorts of error messages:

# 1. Audio or audio-related errors
#
# We want to ignore some audio errors when they are already tracked in a
# bug tracker and after careful review we are confident that they do not
# affect other, unrelated tests. The purpose of CI is to detect new bugs
# and regressions, not to duplicate bug tracking. When test results are
# red most of the time for the same old reasons then most users stop
# paying attention and they miss new errors.

# 2. Non-audio / 3rd party / partner errors
#
# Same rationale as above except we have less interest and less control
# on bug tracking and resolution. Note the Linux kernel is monolithic
# with no internal protection, so any corruption in any subsystem can
# have totally unexpected, non-deterministic and extremely
# time-consuming side-effects in any other subsystem including
# audio. Errors frequently cause corruption because error handling paths
# are almost never tested in any software (buggy error handling is where
# many security bugs lie)

# 3. "False" errors
#
# Messages that look like errors but are not errors. Seem to be fairly
# rare but they do exist. Typically: some debug messages.
#
# Work in progress: fix this code to rely on message _severity_ to get
# fewer false errors (and maybe more actual errors!)
#
# Also known as "false positive" where "positive" confusingly refers to
# finding an error. Errors are negative but finding them is
# positive... let's avoid the term "positive"?

# Basic guidelines
# ----------------
#
# - Errors can come and go and they can also change categories as new
# information is discovered, little is static. Important rule: every
# ignored message must have a link to some other place (typically: a
# bug) where more the latest information can be found and discussed. It
# would be very impractical to use this file itself as a discussion
# space, especially for non-audio discussions. This being said, a
# one-line comment in this file does not hurt and mentioning the error
# type above is useful.
#
# - Patterns ignored should be as long and as specific as possible to
# minimize the risk of ignoring unknown errors. Ignoring unknown kernel
# errors is very dangerous because the Linux kernel is monolithic with
# no internal protection so corruption of any subsystem can have totally
# unexpected, non-deterministic and extremely time-consuming
# side-effects in any other subsystem including audio.
#
# - Platform-specific errors should preferably be ignored by affected
# platforms only for the following reasons:
#
# * Ignoring kernel errors is risky as just described above. The fewer
#   platforms and the smaller the risk to ignore real issues.
#
# * Most platform-specific errors affect _our_ platforms and products so
#   we want to collect as much information as possible to help our
#   partners fix them and especially let them know which platform(s)
#   they can be reproduced on.
#
# * Once the error is fixed, the fewer the platforms and the easier it
#   is to re-test and clean up this file. See cleanup section below.
#
# * If observed on more platforms than initially expected, adding new
#   platforms (or any platform) is a very quick and simple change.

# Cleanup
# -------
#
# We must stop ignoring errors when bugs get fixed. This is of course
# extremely important when _audio_ errors get fixed: otherwise running
# these tests would be pointless! Someone submitting an audio bug fix
# without trying to remove any corresponding error filter in this file
# would be demonstrating an unprofessional lack of bug reproduction and
# testing.
#
# Cleanup is good practice for non-audio errors too to confirm partner
# fixes and to avoid this file growing out of control.
#
# HOWEVER: make sure the fix for a removed error has been cherry-picked
# in _all currently supported versions and releases_! Ask the validation
# team for advice.

# Regular expressions
# -------------------
#
# The use of regular expression is required to catch variations. For
# instance we don't want to have one string per possible PCI ID. HOWEVER
# regular expressions should be kept very basic to they can be easily
# read and searched in the file. For instance if the same message can
# appear with either "hw_start" or "hw_reset" then prefer (some)
# duplication. Who knows, these two messages could prove to be caused by
# two different bugs eventually. Regular expressions are error-prone so
# keep them simple. What is especially error-prone: the slightly
# different and mutually incompatible "flavors" of regular expressions.
#
# This file uses the 'grep -E' regex flavor.

# Test tips
# ---------
#
# Regular expressions are error-prone so they must be tested well. For
# testing changes to this file invoke (temporarily) fake_kern_error() in
# relevant test code. See more info in case-lib/lib.sh.
# fake_kern_error() is useful to test the test code in general.
#
# Append some garbage to an ignore pattern to turn it off. Much easier
# than deleting it.

begin_timestamp=${1:-0}
declare ignore_str

# pwd resolves relative paths
my_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
platform=$("$my_dir"/sof-dump-status.py -p)

# TODO explain
# The first string cannot start by |
ignore_str='error: debugfs write failed to idle -16'

# CML Helios known issue related with xhci_hcd
# https://bugzilla.kernel.org/show_bug.cgi?id=202541
ignore_str="$ignore_str"'|xhci_hcd 0000:00:14\.0: WARN Set TR Deq Ptr cmd failed due to incorrect slot or ep state'

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

# Dell TGL laptop with SoundWire, issues reported by sof-test
ignore_str="$ignore_str"'|ACPI BIOS Error \(bug\):'
ignore_str="$ignore_str"'|ACPI Error:'
ignore_str="$ignore_str"'|acpi device:00: Failed to change power state to D3hot'

# I915, issues reported by sof-test
# BugLink: https://github.com/thesofproject/sof-test/issues/374
ignore_str="$ignore_str"'|i915 0000:00:02\.0: \[drm\] \*ERROR\* TC cold unblock failed'
ignore_str="$ignore_str"'|i915 0000:00:02\.0: \[drm\] \*ERROR\* TC cold block failed'

# DRM issues with kernel v5.10-rc1 https://github.com/thesofproject/linux/pull/2538
ignore_str="$ignore_str"'|\[drm:drm_dp_send_link_address \[drm_kms_helper\]\] \*ERROR\* Sending link address failed with -5'

# CHT devices with USB hub, issues reported by sof-test
# BugLink: https://github.com/thesofproject/sof-test/issues/431
ignore_str="$ignore_str"'|hub 2-.: .'
ignore_str="$ignore_str"'|usb 2-.: .'

# TGL devices with USB 3.1 devices, issues reported by sof-test
# BugLink: https://github.com/thesofproject/sof-test/issues/482
ignore_str="$ignore_str"'|usb 3-.: device descriptor read/64, error .'
ignore_str="$ignore_str"'|usb 3-.: device not accepting address ., error .'

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
# Buglink: https://github.com/thesofproject/sof/issues/3395

ignore_str="$ignore_str"'|sof-audio-pci 0000:00:..\..: status = 0x[0-f]{8} panic = 0x[0-f]{8}'
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

case "$platform" in
    # Audio PCI ID on CML Mantis is [8086:9dc8], which is defined as CNL in linux kernel.
    # https://github.com/thesofproject/linux/blob/topic/sof-dev/sound/soc/sof/sof-pci-dev.c
    icl|cml|cnl)
        # On CML_RVP_SDW, suspend-resume test case failed due to "mei_me 0000:00:16.4: hw_reset failed ret = -62" or with "hw_start" with same error code.
        # https://github.com/thesofproject/sof-test/issues/389
        ignore_str="$ignore_str"'|mei_me 0000:00:16\..: hw_reset failed ret = -62'
        ignore_str="$ignore_str"'|mei_me 0000:00:16\..: hw_start failed ret = -62'

        # On CML_RVP_SDW, NOHZ tick-stop error causes a false failure
        # https://github.com/thesofproject/sof-test/issues/505
        ignore_str="$ignore_str"'|NOHZ tick-stop error: Non-RCU local softirq work is pending, handler #80!!!'

        # CML Mantis occasionally throws Intel(R) Management Engine Interface(mei) errors
        # https://unix.stackexchange.com/questions/109294/mei-00000016-0-init-hw-failure
        ignore_str="$ignore_str"'|mei_me 0000:00:16\..: wait hw ready failed'
        ;;
esac

# below are new error level kernel logs from journalctl --priority=err
# that did not influence system and can be ignored

# systemd issues can be ignored
# seen on mutiple platforms
# systemd[1]: Failed to mount Mount unit for core.
# systemd[1]: Failed to mount Mount unit for gnome-calculator.
# systemd[1]: Failed to mount Mount unit for [UNIT].
ignore_str="$ignore_str"'|systemd\[.\]: Failed to mount Mount unit for'

# initramfs issues can be ignored
ignore_str="$ignore_str"'|Initramfs unpacking failed'

# keyboard issues can be ignored
ignore_str="$ignore_str"'|atkbd serio0: Failed to deactivate keyboard on isa0060/serio0'
ignore_str="$ignore_str"'|atkbd serio0: Failed to enable keyboard on isa0060/serio0'

# smbus issues can be ignored
ignore_str="$ignore_str"'|i801_smbus 0000:00:..\..: Transaction timeout'
ignore_str="$ignore_str"'|i801_smbus 0000:00:..\..: Failed terminating the transaction'
ignore_str="$ignore_str""|i801_smbus 0000:00:..\..: SMBus is busy, can't use it!"
ignore_str="$ignore_str"'|i801_smbus 0000:00:..\..: Failed to allocate irq .: -16'

# SATA related issue can be ignored is it did not break device
ignore_str="$ignore_str"'|ata3: COMRESET failed \(errno=-16\)'

# genirq issues can be ignored
# origin logs seen on GLK platforms
# genirq: Flags mismatch irq 0. 00000080 (i801_smbus) vs. 00015a00 (timer)
ignore_str="$ignore_str"'|genirq: Flags mismatch irq .'

# DMAR warnings can be ignored
# origin logs seen on BDW platforms
# DMAR: [Firmware Bug]: No firmware reserved region can cover this RMRR [0x00000000ad000000-0x00000000af7fffff], contact BIOS vendor for fixes
ignore_str="$ignore_str"'|DMAR: \[Firmware Bug\]: No firmware reserved region can cover this RMRR .'

# dw_dmac logs can be ignored
# origin logs seen on BDW/BYT/CHT platforms
# dw_dmac INTL9C60:00: Missing DT data
# dw_dmac INTL9C60:01: Missing DT data
ignore_str="$ignore_str"'|dw_dmac INTL9C60:..: Missing DT data'

# proc_thermal logs can be ignored
# origin logs seen on CHT platforms
# proc_thermal 0000:00:0b.0: No auxiliary DTSs enabled
ignore_str="$ignore_str"'|proc_thermal 0000:00:..\..: No auxiliary DTSs enabled'

# touch pad logs can be ignored
# origin logs seen on GLK platforms
# elan_i2c i2c-ELAN0000:00: invalid report id data (ff)
ignore_str="$ignore_str"'|elan_i2c i2c-ELAN0000:.*: invalid report id data'

#
# SDW related logs
#

# origin logs seen on CML with RT700 platforms
# rt700 sdw:1:25d:700:0: Bus clash detected
ignore_str="$ignore_str"'|rt700 sdw:.:.*:700:.: Bus clash detected'

# confirm begin_timestamp is in UNIX timestamp format, otherwise search full log
journalctlflag="-k -q --no-pager --utc --output=short-monotonic --no-hostname"
[[ $begin_timestamp =~ ^[0-9]{10} ]] && cmd="journalctl $journalctlflag --since=@$begin_timestamp" || cmd="journalctl $journalctlflag"

declare -p cmd
# check priority err for error message
[[ "$ignore_str" ]] && err=$($cmd --priority=err | grep -vE "$ignore_str") || $($cmd --priority=err)

[[ -z "$err" ]] || {
    echo "$(date -u '+%Y-%m-%d %T %Z')" "[ERROR]" "Caught kernel log error"
    echo "===========================>>"
    echo "$err"
    echo "<<==========================="
    builtin exit 1
}
