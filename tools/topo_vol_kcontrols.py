#!/usr/bin/env python3

"""Parses the .tplg file argument and returns a list of volume
kcontrols, one per line.

Pro tip: try using these commands _interactively_ with ipython3
"""

# Keep this script short and simple. If you want to get something else
# from .tplg files, create another script.

import sys
from tplgtool2 import TplgBinaryFormat, TplgType, DapmType, SofVendorToken, has_wname_prefix

TPLG_FORMAT = TplgBinaryFormat()


def main():
    "Main"

    parsed_tplg = TPLG_FORMAT.parse_file(sys.argv[1])

    # pylint: disable=invalid-name
    DAPMs = [
        item for item in parsed_tplg if item.header.type == TplgType.DAPM_WIDGET.name
    ]

    for dapm in DAPMs:
        gain_blocks = [b for b in dapm.blocks if b.widget.id == DapmType.PGA.name]

        for gb in gain_blocks:
            # debug
            # print(f"{gb.widget.id}: {gb.widget.name}")
            print_volume_kcontrols(gb)


def print_volume_kcontrols(gain_block):
    "Print volume kcontrols"

    # Either 1 volume kcontrol, or 1 volume + 1 switch
    assert gain_block.widget.num_kcontrols in (1, 2)

    # A switch is either a DapmType.SWITCH, or DapmType.MIXER
    # with a max "volume" = 1. Don't include switches here.
    volume_kcontrols = [
        kc
        for kc in gain_block.kcontrols
        if kc.hdr.type == DapmType.MIXER.name and kc.body.max != 1
    ]

    assert len(volume_kcontrols) == 1

    wname_prefix = (
        f"{gain_block.widget.name} " if has_wname_prefix(gain_block.widget) else ""
    )

    for vkc in volume_kcontrols:
        print(wname_prefix + vkc.hdr.name)


if __name__ == "__main__":
    main()
