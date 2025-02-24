#!/usr/bin/env python3

"""Parses the .tplg file argument and returns a list of effect
kcontrols of BYTES type, one per line.

Pro tip: try using these commands _interactively_ with ipython3
"""

# Keep this script short and simple. If you want to get something else
# from .tplg files, create another script.

import sys
from tplgtool2 import TplgBinaryFormat, TplgType, DapmType, has_wname_prefix

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

if __name__ == "__main__":
    main()
