#!/usr/bin/env python3

"""Parses the .tplg file argument and returns a list of effect
kcontrols of BYTES type, one per line.

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
    component = sys.argv[2]

    # pylint: disable=invalid-name
    DAPMs = [
        item for item in parsed_tplg if item.header.type == TplgType.DAPM_WIDGET.name
    ]

    for dapm in DAPMs:
        effect_blocks = [b for b in dapm.blocks if b.widget.id == DapmType.EFFECT.name]

        for gb in effect_blocks:
            # debug
            # print(f"{gb.widget.id}: {gb.widget.name}")
            if gb.widget.name == component:
            	print_bytes_kcontrols(gb)


def print_bytes_kcontrols(effect_block):
    "Print bytes kcontrols"

    bytes_kcontrols = [
        kc
        for kc in effect_block.kcontrols
        if kc.hdr.type == 'BYTES'
    ]

    wname_prefix = (
        f"{effect_block.widget.name} " if has_wname_prefix(effect_block.widget) else ""
    )

    for vkc in bytes_kcontrols:
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
