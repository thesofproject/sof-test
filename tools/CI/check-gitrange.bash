#!/bin/bash
# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2018 Intel Corporation. All rights reserved.

set -e

usage()
{
    cat <<EOFUSAGE
Sample usage:

    $0 origin/master... text/x-shellscript   shellcheck  -x -f gcc

    $0 origin/master... text/x-python        pylint  --disable=C

EOFUSAGE

    exit 1
}

main()
{
    # git outputs relative paths
    local git_top; git_top=$(git rev-parse --show-toplevel)
    cd "$git_top"

    local diffrange="$1"; shift || usage

    printf '%s checking diff range: %s\n\n' "$0" "$diffrange"

    local checked_ftype="$1"; shift || usage
    file --list | grep -qF "$checked_ftype" ||
        die 'The file command does not know what %s is\n' "$checked_ftype"

    local checker="$1"; shift || usage
    type "$checker" || die 'Checker %s not found\n' "$checker"

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
        if  [ x"$checked_ftype" = x"$ftype" ]; then
            printf '\n\n  ----- %s' "$checker"
            printf ' %s' "$@"
            printf ' %s ----\n\n' "$fname"
            "$checker" "$@" "$fname"  || : $((failed_files++))
        fi

    done < <(git diff --name-only --diff-filter=d "$diffrange" -- )

    return $failed_files
}


die()
{
    >&2 printf '%s ERROR: ' "$0"
    # We want die() to be usable exactly like printf
    # shellcheck disable=SC2059
    >&2 printf "$@"
    exit 1
}

main "$@"
