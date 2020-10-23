#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2018 Intel Corporation. All rights reserved.

set -e

# Sample usage:
#
#   $  shellcheck-gitrange.bash origin/master... [ -f gcc ]

main()
{
    # The rest of args is passed as is to shellcheck
    local diffrange="$1"; shift

    printf '%s checking diff range: %s\n\n' "$0" "$diffrange"

    # Triple dot "git log A...B" includes commits not relevant to triple
    # dot "git diff A...B"
    local logrange=${diffrange/.../..}
    ( set -x
      # also a sanity check of the argument
      git --no-pager log --oneline --graph --stat --max-count=40 "$logrange" --
    )

    local fname ftype failed_files=0

    # https://mywiki.wooledge.org/BashFAQ/001
    while IFS=  read -r fname; do

         # "file" can fail and return 0. This prints "No such file or
         # directory".
        stat "$fname" > /dev/null
        ftype=$(file --brief --mime-type "$fname")
        if  [ x'text/x-shellscript' = x"$ftype" ]; then
            printf '\n\n  ----- shellcheck %s ----\n\n' "$fname"
            shellcheck -x "$@" "$fname"  || : $((failed_files++))
        fi

    done < <(git diff --name-only --diff-filter=d "$diffrange" -- )

    return $failed_files
}

main "$@"
