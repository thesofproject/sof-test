#!/usr/bin/env python3

"""
Do not make this script longer or more complicated. Use it as starting
point if needed.

Pro tip: try these commands _interactively_ from `ipython3`
"""

import sys
import tplgtool2

tplgFormat = tplgtool2.TplgBinaryFormat()

parsedTplg = tplgFormat.parse_file(sys.argv[1])

print(parsedTplg)
