#!/bin/bash -e
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2018 Intel Corporation. All rights reserved.

insert_module() {

    local MODULE="$1"

    if modinfo "$MODULE" &> /dev/null ; then
        echo "Inserting $MODULE"
        sudo modprobe "$MODULE"
    else
        echo "skipping $MODULE, not in tree"
    fi
}

# Test sudo first, not after dozens of SKIP
sudo true

insert_module snd_soc_da7213
insert_module snd_soc_da7219

insert_module snd_soc_rt274
insert_module snd_soc_rt286
insert_module snd_soc_rt298
insert_module snd_soc_rt5640
insert_module snd_soc_rt5645
insert_module snd_soc_rt5651
insert_module snd_soc_rt5660
insert_module snd_soc_rt5670
insert_module snd_soc_rt5677
insert_module snd_soc_rt5677_spi
insert_module snd_soc_rt5682_i2c
insert_module snd_soc_rt5682_sdw

insert_module snd_soc_pcm512x_i2c
insert_module snd_soc_wm8804_i2c
insert_module snd_soc_max98357a
insert_module snd_soc_max98090
insert_module snd_soc_max98373
insert_module snd_soc_max98373_i2c
insert_module snd_soc_max98373_sdw

insert_module snd_soc_rt700
insert_module snd_soc_rt711
insert_module snd_soc_rt1308
insert_module snd_soc_rt1308_sdw
insert_module snd_soc_rt715
insert_module snd_soc_rt1011

insert_module snd_sof_acpi_intel_byt
insert_module snd_sof_acpi_intel_bdw

insert_module snd_sof_pci_intel_tng
insert_module snd_sof_pci_intel_apl
insert_module snd_sof_pci_intel_cnl
insert_module snd_sof_pci_intel_icl
insert_module snd_sof_pci_intel_tgl

insert_module snd_sof_acpi
insert_module snd_sof_pci

insert_module snd_usb_audio

# without the status check force quit
builtin exit 0
