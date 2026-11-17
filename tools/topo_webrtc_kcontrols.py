#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause

"""Inspect compiled SOF .tplg files for WebRTC effect widgets and controls."""

import argparse
import os
import sys

from tplgtool2 import DapmType, TplgBinaryFormat, TplgType

WEBRTC_TYPES = ("hpf", "vad", "ns2", "ns", "agc", "aec")


def parse_args():
    """Parse CLI options."""
    parser = argparse.ArgumentParser(
        description="List WebRTC widgets and mixer kcontrols from .tplg binary."
    )
    parser.add_argument(
        "tplg",
        help="Path(s) to compiled topology file(s), separated by comma or colon",
    )
    parser.add_argument(
        "--type",
        choices=("all",) + WEBRTC_TYPES,
        default="all",
        help="Filter to a specific WebRTC module type (default: all)",
    )
    return parser.parse_args()


def detect_webrtc_type(widget_name):
    """Return canonical WebRTC module type string for a widget name, or None."""
    if not widget_name.startswith("webrtc-"):
        return None
    for mod_type in WEBRTC_TYPES:
        prefix = f"webrtc-{mod_type}"
        if widget_name == prefix or widget_name.startswith(prefix + "."):
            return mod_type
    return None


def iter_webrtc_controls(tplg_paths, target_type="all"):
    """Yield (mod_type, widget_name, kctrl_name, kctrl_type) tuples."""
    tplg_format = TplgBinaryFormat()
    seen = set()

    for path in tplg_paths:
        if not path:
            continue
        parsed = tplg_format.parse_file(path)
        for item in parsed:
            if item.header.type != TplgType.DAPM_WIDGET.name:
                continue
            for block in item.blocks:
                if block.widget.id != DapmType.EFFECT.name:
                    continue
                mod_type = detect_webrtc_type(block.widget.name)
                if not mod_type or target_type not in ("all", mod_type):
                    continue
                kcontrols = getattr(block, "kcontrols", []) or []
                if not kcontrols:
                    entry = (mod_type, block.widget.name, "", "")
                    if entry not in seen:
                        seen.add(entry)
                        yield entry
                    continue
                for kc in kcontrols:
                    kc_type = str(kc.hdr.type)
                    entry = (mod_type, block.widget.name, kc.hdr.name, kc_type)
                    if entry not in seen:
                        seen.add(entry)
                        yield entry


def main():
    """Entry point."""
    args = parse_args()
    raw_paths = args.tplg.replace(":", ",").split(",")
    tplg_paths = [os.path.abspath(p.strip()) for p in raw_paths if p.strip()]

    for mod_type, wname, kname, ktype in iter_webrtc_controls(tplg_paths, args.type):
        print(f"{mod_type}|{wname}|{kname}|{ktype}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
