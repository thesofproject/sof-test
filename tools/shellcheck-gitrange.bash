#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2018 Intel Corporation. All rights reserved.

set -e

# Sample usage:
#
#    shellcheck-gitrange.bash HEAD~5.. [ -f gcc ]

main()
{
    local gitrange="$1"; shift

    printf '%s checking range %s\n' "$0" "$gitrange"
    # sanity check
    git rev-list --quiet "$gitrange" --

    local fname ftype failed_files=0

    # https://mywiki.wooledge.org/BashFAQ/001
    while IFS=  read -r fname; do

        ftype=$(file --brief --mime-type "$fname")
        if  [ x'text/x-shellscript' = x"$ftype" ]; then
            printf '\n\n  ----- shellcheck %s ----\n' "$fname"
            shellcheck "$@" "$fname"  || : $((failed_files++))
        fi

    done < <(git diff --name-only --diff-filter=d "$gitrange" -- )

    return $failed_files
}

main "$@"
