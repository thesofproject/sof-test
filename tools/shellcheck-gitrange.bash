#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2018 Intel Corporation. All rights reserved.

set -e

# Sample usage:
#
#   $  shellcheck-gitrange.bash HEAD~5.. [ -f gcc ]

main()
{
    # The rest of args is passed as is to shellcheck
    local gitrange="$1"; shift

    printf '%s checking range %s\n\n' "$0" "$gitrange"
    # also a sanity check
    git log --oneline "$gitrange" -- | cat # no pager

    local fname ftype failed_files=0

    # https://mywiki.wooledge.org/BashFAQ/001
    while IFS=  read -r fname; do

        ftype=$(file --brief --mime-type "$fname")
        if  [ x'text/x-shellscript' = x"$ftype" ]; then
            printf '\n\n  ----- shellcheck %s ----\n\n' "$fname"
            shellcheck "$@" "$fname"  || : $((failed_files++))
        fi

    done < <(git diff --name-only --diff-filter=d "$gitrange" -- )

    return $failed_files
}

main "$@"
