#!/usr/bin/env python3

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2022 Intel Corporation. All rights reserved.

# Run with --help for a description of this script

import argparse
import pytest
import os


def test_bpftrace_conditions(bpftrace_condition):
    """ This is the test function that is called by pytest """
    (_name, condition, bpftrace_vars) = bpftrace_condition
    condition_with_vars = condition
    for key, val in bpftrace_vars.items():
        condition_with_vars = condition_with_vars.replace(key, val)
    has_syntax_error = False
    try:
        # Eval does not decrease security as the spec file already embeds shell commands anyway
        # pylint: disable=eval-used
        if not eval(condition_with_vars):
            pytest.fail(
                f"Failed condition: {condition}. Evaluated to {condition_with_vars}.", pytrace=False)
    except SyntaxError:
        has_syntax_error = True
    # We need pytest.fail to be called outside of the try/except block so the unneeded stack trace is not included
    if has_syntax_error:
        pytest.fail(
            f"Invalid condition: {condition}. Are you sure the bpftrace script outputs necessary variables?", pytrace=False)


def main():
    """ This calls pytest, which runs the test above """
    parser = argparse.ArgumentParser(
        description="""
This script takes as an argument a path to a json file that contains test cases.
See readme.md for more details.
"""
    )
    parser.add_argument("spec_file", type=argparse.FileType('r'))
    args = parser.parse_args()
    os.chdir(os.path.dirname(os.path.abspath(args.spec_file.name)))
    pytest.main([parser.prog, "-s", "-v", "-rA",
                "--spec_file", os.path.basename(args.spec_file.name)])


if __name__ == "__main__":
    main()
