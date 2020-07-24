#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2018 Intel Corporation. All rights reserved.

set -e

printf 'TRAVIS_COMMIT_RANGE=%s\n' "${TRAVIS_COMMIT_RANGE}"
printf 'TRAVIS_BRANCH=%s\n' "${TRAVIS_BRANCH}"

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
    ( set -x; set +e
      # also a sanity check of the argument
      git --no-pager log --oneline --decorate --graph --stat --max-count=40 "$logrange" --
      git --no-pager log --oneline --decorate --graph --stat --max-count=40 HEAD master --
      git --no-pager log --oneline --decorate --graph --stat --max-count=40 HEAD origin/master --
    )

    local fname ftype failed_files=0

    # https://mywiki.wooledge.org/BashFAQ/001
    while IFS=  read -r fname; do

        ftype=$(file --brief --mime-type "$fname")
        if  [ x'text/x-shellscript' = x"$ftype" ]; then
            printf '\n\n  ----- shellcheck %s ----\n\n' "$fname"
            shellcheck -x "$@" "$fname"  || : $((failed_files++))
        fi

    done < <(git diff --name-only --diff-filter=d "$diffrange" -- )

    return $failed_files
}

main "$@"
