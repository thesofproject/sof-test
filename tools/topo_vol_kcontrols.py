#!/usr/bin/env python3

"""Parses the .tplg file argument and returns a list of volume
kcontrols, one per line.

Pro tip: try using these commands _interactively_ with ipython3
"""

# Keep this script short and simple. If you want to get something else
# from .tplg files, create another script.

import sys
from tplgtool2 import TplgBinaryFormat, TplgType, DapmType, SofVendorToken

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


# This could probably be moved to tplgtool2.py?
def has_wname_prefix(widget):
    """Is the kcontrol name prefixed with the widget name? ("PGAxx" or "Dmicxx")
    Check SOF_TKN_COMP_NO_WNAME_IN_KCONTROL_NAME"""

    wname_elems = [
        prv.elems
        for prv in widget.priv
        if prv.elems[0].token
        == SofVendorToken.SOF_TKN_COMP_NO_WNAME_IN_KCONTROL_NAME.name
    ]

    if len(wname_elems) == 0:  # typically: topo v1
        no_wname_prefix = 0
    elif len(wname_elems) == 1:  # typically: topo v2
        assert len(wname_elems[0]) == 1
        no_wname_prefix = wname_elems[0][0].value
    else:
        assert False, f"Unexpected len of wname_elems={wname_elems}"

    assert no_wname_prefix in (0, 1)

    # Double-negation: "no_wname false" => prefix
    return not no_wname_prefix


if __name__ == "__main__":
    main()
