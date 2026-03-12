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

# You don't need to change this file for errors specific to unusual
# configurations or unusual devices. Instead, define a
# sof_local_extra_kernel_ignores=( ... ) array in either
# /etc/sof/local_config.bash or ${SCRIPT_HOME}/case-lib/local_config.bash
# This is also a convenient way to stage and test future `ignore_str` changes
# without git acrobatics.
#
# Detailed explanation  in commits 83f5e4190e9f21bf and f94cdc772758692

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

# Don't look at journalctl logs before this time in seconds since
# 1970. Defaults to zero which is a no-op because we always use -k or
# -b.
begin_timestamp=${1:-0000000000}

declare ignore_str

# pwd resolves relative paths
test_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
platform=$("$test_dir"/tools/sof-dump-status.py -p)

# shellcheck source=case-lib/lib.sh
source "$test_dir"/case-lib/lib.sh
# The lib.sh sourced hijack.sh, which trapped exit to use our
# exit handler, because this is not a test case, we don't need
# the exit handler.
trap - EXIT

# The first string cannot start by |

# TODO explain why we ignore this one and where
ignore_str='error: debugfs write failed to idle -16'

#TWLignore DRM errors
ignore_str="$ignore_str"'|i915 [[:digit:].:]+: \[drm\] \*ERROR\* Unclaimed access detected prior to suspending'

#Soundwire igone parity erros
ignore_str="$ignore_str"'|sdw:[0-9]:[0-9]:[A-Za-z0-9]*:[A-Za-z0-9]*:[0-9]*: Parity error detected'

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
ignore_str="$ignore_str"'|usb .+: (Enable|Disable) of device-initiated .+ failed\.'
ignore_str="$ignore_str"'|thermal thermal_zone.*: failed to read out thermal zone \(-61\)'

# Ignore all ISH related issues. We have no shared flows between ISH and audio.
ignore_str="$ignore_str"'|intel_ish_ipc 0000:00:[0-9]+\.0:'

# Dell CML-U laptop with SoundWire, issues reported by sof-test
# BugLink: https://github.com/thesofproject/sof-test/issues/307
ignore_str="$ignore_str"'|: authentication with ..:..:..:..:..:.. timed out'

# Dell TGL laptop with SoundWire, issues reported by sof-test
ignore_str="$ignore_str"'|ACPI BIOS Error \(bug\):'
ignore_str="$ignore_str"'|ACPI Error:'
ignore_str="$ignore_str"'|acpi device:00: Failed to change power state to D3hot'

# I915, issues reported by sof-test
# BugLink: https://github.com/thesofproject/sof-test/issues/374
ignore_str="$ignore_str"'|i915 0000:00:02\.0: \[drm\] \*ERROR\* TC cold unblock failed'
ignore_str="$ignore_str"'|i915 0000:00:02\.0: \[drm\] \*ERROR\* TC cold block failed'
# Dell TGLH SIF 15 laptop. ignore CPU stepping warning
ignore_str="$ignore_str"'|i915 0000:00:02\.0: \[drm\] \*ERROR\* This is a pre-production stepping. It may not be fully functional'
# An error observed on ICL RVP: "[drm] *ERROR* CPU pipe A FIFO underrun"
ignore_str="$ignore_str"'|\[drm\] \*ERROR\* CPU pipe . FIFO underrun'
# BugLink: https://github.com/thesofproject/sof-test/issues/753
# see also: https://github.com/thesofproject/linux/blob/57a88a71b411ff44a7568db05226ec2727bf91c1/drivers/gpu/drm/i915/display/intel_crtc.c#L580
ignore_str="$ignore_str"'|\[drm\] \*ERROR\* Atomic update failure on pipe . \(start=[0-9]+ end=[0-9]+\) time [0-9]+ us, min [0-9]+, max [0-9]+, scanline start [0-9]+, end [0-9]+'

# DRM issues with kernel v5.10-rc1 https://github.com/thesofproject/linux/pull/2538
ignore_str="$ignore_str"'|\[drm:drm_dp_send_link_address \[drm_kms_helper\]\] \*ERROR\* Sending link address failed with -5'

# Generic USB issue reported on TGL, CML, BDW
# https://sof-ci.01.org/linuxpr/PR2812/build5534/devicetest/
# usb 3-8: cannot get connectors status: req = 0x81, wValue = 0x700, wIndex = 0xa00, type = 0
# usb 3-13: cannot get connectors status: req = 0x81, wValue = 0x700, wIndex = 0xa00, type = 0
# usb 1-1.1: cannot get connectors status: req = 0x81, wValue = 0x700, wIndex = 0xa00, type = 0
# usb 1-3: cannot get connectors status: req = 0x81, wValue = 0x700, wIndex = 0xa00, type = 0
ignore_str="$ignore_str"'|usb .+-.+: cannot get connectors status:'

# CHT devices with USB hub, issues reported by sof-test
# BugLink: https://github.com/thesofproject/sof-test/issues/431
ignore_str="$ignore_str"'|hub [23]-.+: hub_ext_port_status failed'
ignore_str="$ignore_str"'|usb [23]-.+: Failed to suspend device, error'

# TGL devices with USB 3.1 devices, issues reported by sof-test
# BugLink: https://github.com/thesofproject/sof-test/issues/482
# CML Helios reported usb errors in kmod test, and caused false failure
# BugLink: https://github.com/thesofproject/sof-test/issues/567
ignore_str="$ignore_str"'|usb .-.+: device descriptor read/.+, error'
ignore_str="$ignore_str"'|usb .-.+: device not accepting address .+, error'
ignore_str="$ignore_str"'|usb usb.-port.+: unable to enumerate USB device'

# found on TGLU_SKU0A32_SDCA with check-playback-100sec.sh, internal daily test #5745
# see also: https://github.com/thesofproject/linux/blob/b73297355e03ffdff62e3d7a6438934f05c58f54/drivers/usb/core/hub.c#L5563
# usb 3-8-port4: disabled by hub (EMI?), re-enabling...
ignore_str="$ignore_str"'|(usb|hub) .+: disabled by hub \(EMI\?\), re-enabling\.\.\.'

# Devices with IGB network interfaces. Since we have multiple issues we ignore
# all messages from this driver, e.g.
# igb 0000:01:00.0 enp1s0: Reset adapter'
# igb 0000:01:00.0: exceed max 2 second'
# BugLink: https://github.com/thesofproject/sof-test/issues/617
ignore_str="$ignore_str"'|igb 0000:..:..\..*'

# asix error in TGLH_0A5E_SDW, TGLH_RVP_HDA
# kernel: asix 3-3.1:1.0 enx000ec65356e1: asix_rx_fixup() Bad Header Length 0x0, offset 4
# kernel: asix 3-12.1:1.0 enx000ec668ad2a: asix_rx_fixup() ...
# kernel: asix 3-4:1.0 enx8cae4cfe1882: asix_rx_fixup() Bad Header Length 0x4b203a6e, offset 4
# buglink: https://github.com/thesofproject/sof-test/issues/622
ignore_str="$ignore_str"'|asix .-.+:.\.. en.+: asix_rx_fixup\(\) Bad Header Length'

# asix error in TGLH_0A5E_SDW
# kernel: asix 3-3.1:1.0 enx000ec65356e1: Failed to enable software MII access
# kernel: asix 3-3.1:1.0 enx000ec65356e1: Failed to enable hardware MII access
# buglink: https://github.com/thesofproject/sof-test/issues/565
# buglink: https://github.com/thesofproject/sof-test/issues/664
ignore_str="$ignore_str"'|asix .-.+\..:.\.. en.+: Failed to .+'

# Ignore all types of mei_me errors
# On CML_RVP_SDW, suspend-resume test case failed due to "mei_me 0000:00:16.4: hw_reset failed ret = -62" or
# with "hw_start" with same error code
# https://github.com/thesofproject/sof-test/issues/389
# CML Mantis occasionally throws Intel(R) Management Engine Interface(mei) errors
# https://unix.stackexchange.com/questions/109294/mei-00000016-0-init-hw-failure
# TGLH_SKU0A70_HDA and WHL_UPEXT_HDA_ZEPHYR, suspend-resume test cases failed due to "mei_me 0000:00:16.0: wait hw ready failed"
# https://github.com/intel-innersource/drivers.audio.ci.sof-framework/issues/246
ignore_str="$ignore_str"'|mei_me 0000:00:16\..: .+'

# Ignore all types of mei_gsc_proxy errors
ignore_str="$ignore_str"'|mei_gsc_proxy .+'

# Ignore all mei0 errors
ignore_str="$ignore_str"'|mei mei0: .+'

case "$platform" in
    # Audio PCI ID on CML Mantis is [8086:9dc8], which is defined as CNL in linux kernel.
    # https://github.com/thesofproject/linux/blob/topic/sof-dev/sound/soc/sof/sof-pci-dev.c
    icl|cml|cnl)
        # On CML_RVP_SDW, NOHZ tick-stop error causes a false failure
        # https://github.com/thesofproject/sof-test/issues/505
        ignore_str="$ignore_str"'|NOHZ tick-stop error: Non-RCU local softirq work is pending, handler #80!!!'
        ;;
    adl|adl-s)
        # i915 AUX logs can be ignored
        # origin logs seen on ADLS platforms
        # i915 0000:00:02.0: [drm] *ERROR* AUX A/DDI A/PHY A: did not complete or timeout within 10ms (status 0xad4003ff)
        # i915 0000:00:02.0: [drm] *ERROR* AUX A/DDI A/PHY A: not done (status 0xad4003ff)
        ignore_str="$ignore_str"'|i915 [[:digit:].:]+: \[drm\] \*ERROR\* AUX .+'
        # i915 Unclaimed access detected, something to do with DMC in ADL
        # unclaimed access happens when try to read/write something that is powered down
        # issue link : internal issue #243
        ignore_str="$ignore_str"'|i915 [[:digit:].:]+: \[drm\] \*ERROR\* Unclaimed access detected .+'
        # i915 firmware loading error on ADLP_SKU0B00_SDCA
        # BugLink: https://github.com/thesofproject/sof-test/issues/1048
        ignore_str="$ignore_str"'|i915 [[:digit:].:]+: \[drm\] \*ERROR\* GT0: GuC initialization failed'
        ignore_str="$ignore_str"'|i915 [[:digit:].:]+: \[drm\] \*ERROR\* GT0: Enabling uc failed'
        ignore_str="$ignore_str"'|i915 [[:digit:].:]+: \[drm\] \*ERROR\* GT0: Failed to initialize GPU'
        ;;
    tgl)
        # Bug Report: https://github.com/thesofproject/sof-test/issues/838
        # New TGLU_UP_HDA_ZEPHYR device reporting "TPM interrupt not working" errors.
        ignore_str="$ignore_str"'|kernel: tpm tpm0: \[Firmware Bug\]: TPM interrupt not working, polling instead'
        # Bug Report: https://github.com/thesofproject/sof-test/issues/936
        ignore_str="$ignore_str"'|kernel: tpm tpm0: Operation Canceled'
        ;;
    ehl)
        # i915 crtc logs can be ignored
        # origin logs seen on EHL_RVP_I2S platforms
        # i915 0000:00:02.0: [drm] *ERROR* Suspending crtc's failed with -22
        ignore_str="$ignore_str""|i915 [[:digit:].:]+: \[drm\] \*ERROR\* Suspending crtc's failed with -[[:digit:]]+"
	;;
    rpl)
	# HID ACPI error in suspend-resume
        # https://github.com/thesofproject/sof-test/issues/980
        # i2c_hid_acpi i2c-VEN_0488:00: i2c_hid_get_input: incomplete report (20/42405)
        ignore_str="$ignore_str""|i2c_hid_acpi i2c-VEN_0488:00: i2c_hid_get_input: incomplete report"
    ;;
    lnl|ptl)
        # ignore the ACPI error on LNL and PTL.
        # kernel: ACPI: \: Can't tag data node
        ignore_str="$ignore_str""|kernel: ACPI: \\\\: Can't tag data node"
        ignore_str="$ignore_str""|kernel: xe 0000:00:02.0: \[drm\] \*ERROR\* Tile0: GT1: Timed out wait for G2H, fence [0-9]+, action [0-9]+, done no"
        ignore_str="$ignore_str""|kernel: xe 0000:00:02.0: \[drm\] \*ERROR\* Tile0: GT1: PF: Failed to push self configuration \(-ETIME\)"
esac

# 'failed to change power setting' and other errors observed at boot
# time on one TGLU_VOLT_SDW. Internal issue #174.  GOODIX touchscreen
# /sys/devices/pci0000:00/0000:00:15.1/i2c_designware.1/i2c-1/i2c-GDIX0000:00
#
# Also: Failed to fetch the HID Descriptor / unexpected bcdVersion (0x0000)
# on one CML_HEL_RT5682
ignore_str="$ignore_str"'|kernel: i2c_hid_acpi i2c-GDIX0000:00'


# below are new error level kernel logs from journalctl --priority=err
# that did not influence system and can be ignored

# Ignore IRQ conflict errors - non-audio hardware issue on WCL platform
# This not affect audio functionality
ignore_str="$ignore_str"'|irq [[:digit:]]+: nobody cared'
ignore_str="$ignore_str"'|try booting with the "irqpoll" option'
ignore_str="$ignore_str"'|Disabling IRQ #[[:digit:]]+'
ignore_str="$ignore_str"'|kernel: handlers:'
ignore_str="$ignore_str"'|\[<[0-9a-f]+>\]'

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

# PS2/serial failures
ignore_str="$ignore_str""|i8042: Can't read CTR while initializing i8042"
# Linux kernel commit 32de4b4f9dfa upgraded this generic warning to an error
ignore_str="$ignore_str""|i8042: probe with driver i8042 failed"

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
# origin logs seen on TGL platforms
# DMAR: DRHD: handling fault status reg 3
# DMAR: [DMA Read] Request device [00:02.0] PASID ffffffff fault addr 70ad5000 [fault reason 07] Next page table ptr is invalid
# origin logs seen on TGL and TGLH platforms
# DMAR: [DMA Read NO_PASID] Request device [0x00:0x02.0] fault addr 0x7c592000 [fault reason 0x06] PTE Read access is not set
ignore_str="$ignore_str"'|DMAR: DRHD: handling fault status reg 3'
ignore_str="$ignore_str"'|DMAR: \[DMA Read.*\] Request device'

# TME related warnings can be ignored
# x86/mktme: No known encryption algorithm is supported: 0x4
ignore_str="$ignore_str"'|x86/mktme: No known encryption algorithm is supported: .+'

# r8152 networking warnings can be ignored
# orginal logs seen on  TGLU_SKU0A32_SDCA
# kernel: r8152 3-8.1:1.0 enx34298f909f0b: can't resubmit intr, status -1
ignore_str="$ignore_str""|r8152 [[:digit:].:-]+ [a-z0-9]+: can't resubmit intr, status -."

# dw_dmac logs can be ignored
# origin logs seen on BDW/BYT/CHT platforms
# dw_dmac INTL9C60:00: Missing DT data
# dw_dmac INTL9C60:01: Missing DT data
ignore_str="$ignore_str"'|dw_dmac INTL9C60:..: Missing DT data'

# proc_thermal logs can be ignored
# origin logs seen on CHT platforms
# proc_thermal 0000:00:0b.0: No auxiliary DTSs enabled
ignore_str="$ignore_str"'|proc_thermal 0000:00:..\..: No auxiliary DTSs enabled'
ignore_str="$ignore_str"'|kernel: proc_thermal_pci 0000:00:04.0: failed to add RAPL MMIO interface'

# touch pad logs can be ignored
# origin logs seen on GLK platforms
# elan_i2c i2c-ELAN0000:00: invalid report id data (ff)
ignore_str="$ignore_str"'|elan_i2c i2c-ELAN0000:.*: invalid report id data'

# GLK another touch pad errors to be ignored
# BugLink: https://github.com/thesofproject/sof-test/issues/735
ignore_str="$ignore_str"'|elan_i2c i2c-ELAN0000:.*: reading cmd \(0x[A-Fa-f0-9]{4}\) fail'
ignore_str="$ignore_str"'|elan_i2c i2c-ELAN0000:.*: failed to read current power state:'

# iwlwifi net adaptor logs can be ignored
# origin logs seen on CML platforms
# iwlwifi 0000:00:14.3: Direct firmware load for iwlwifi-QuZ-a0-hr-b0-56.ucode failed with error -2
# iwlwifi 0000:00:14.3: Direct firmware load for iwl-debug-yoyo.bin failed with error -2
# BugLink: https://github.com/thesofproject/sof-test/issues/307
# iwlwifi 0000:00:14.3: Microcode SW error detected. Restarting 0x0.'
# BugLink: https://github.com/thesofproject/sof-test/issues/578
# iwlwifi 0000:00:14.3: No beacon heard and the time event is over already...
ignore_str="$ignore_str"'|iwlwifi [[:digit:].:]+: '

# This can happen when starting snapd at boot time or when re-installing it.
# https://github.com/thesofproject/sof-test/issues/874
ignore_str="$ignore_str"'|I/O error, dev loop., sector 0 op 0x0:.READ. flags 0x80700'

# NVME harmless errors added in 5.18-rc1
# https://github.com/thesofproject/sof-test/issues/888
ignore_str="$ignore_str"'|nvme0: Admin Cmd\(0x[[:digit:]]+\), I/O Error \(sct 0x0 / sc 0x2\)'

ignore_str="$ignore_str"'|kernel: xe 0000:00:02.0: \[drm\]'

#
# SDW related logs
#

# This expects an array like for instance:
#    sof_local_extra_kernel_ignores=(-e 'error 1' -e err2)
# Arrays
# - provide whitespace/quoting safety
# - can be empty/optional
# - can be arbitrarily complex. Best avoided but only on specific systems anyway.
# shellcheck disable=SC2154
if &>/dev/null declare -p sof_local_extra_kernel_ignores; then
    dlogw "Ignoring extra errors on this particular system:"
    declare -p sof_local_extra_kernel_ignores
fi

# confirm begin_timestamp is in UNIX timestamp format, otherwise search full log
if [[ $begin_timestamp =~ ^[0-9]{10} ]]; then
    cmd="journalctl_cmd --since=@$begin_timestamp"
else
    die "Invalid begin_timestamp $1 argument: $begin_timestamp"
fi

declare -p cmd

if err=$($cmd --priority=err |
          grep -v -E -e "$ignore_str" "${sof_local_extra_kernel_ignores[@]}"); then

    type journalctl_cmd
    echo "$(date -u '+%Y-%m-%d %T %Z')" "[ERROR]" "Caught kernel log error"
    echo "===========================>>"
    echo "$err"
    echo "<<==========================="
    builtin exit 1

fi
