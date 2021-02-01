#!/bin/bash

# function dpkg_version_ge uses dpkg to get the package version
# and compares it with the specified version. If the package version
# is less than the specified version, it means the version dependency
# is not met and return 1.
# Args: $1: package name
#       $2: specified version
dpkg_version_ge()
{
    local ver
    ver=$(dpkg -l "$1" |grep "$1" | awk '{print $3}')
    [[ -z "$ver" ]] && die "failed to get $1 version"
    dlogi "find $1 version  $ver"
    version_ge "$ver" "$2"
}

# function version_ge compares the 2 versions specified in the parameters.
version_ge()
{
    printf '%s\n' "$2" "$1" | sort -V -C
}
