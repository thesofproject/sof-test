#!/usr/bin/env python3

"""
Simple demo showing how to get started with the tplgtool2.py parser.

Tip: try these commands interactively in "ipython3"; with TAB completion.
"""

import sys
from tplgtool2 import TplgBinaryFormat, TplgType, DapmType

TPLG_FORMAT = TplgBinaryFormat()


def main():
    "Main function"

    parsed_tplg = TPLG_FORMAT.parse_file(sys.argv[1])

    # pylint: disable=invalid-name
    DAPMs = [
        item for item in parsed_tplg if item.header.type == TplgType.DAPM_WIDGET.name
    ]

    for dapm in DAPMs:

        schedulers = [b for b in dapm.blocks if b.widget.id == DapmType.SCHEDULER.name]

        assert len(schedulers) <= 1

        sched = schedulers[0].widget.name if len(schedulers) == 1 else "none"

        print(f"\n --- SCHEDULER = {sched} ------- \n")

        for block in dapm.blocks:
            if block.widget.id == DapmType.SCHEDULER.name:
                continue
            print(f"{block.widget.id}: {block.widget.name}")


if __name__ == "__main__":
    main()
