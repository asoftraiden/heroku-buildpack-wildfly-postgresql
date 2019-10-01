#!/usr/bin/env bash

# Determines whether a given path is relative to a directory
# or not. The function assumes that an absolute path starts
# with a leading '/'.
#
# Params:
#   $1:  path  the path to check
#
# Returns:
#   0: The path is relative
#   1: The path is absolute
_is_relative_path() {
    local path="$1"

    ! [[ "${path}" =~ ^/ ]]
}

# Resolves a given path to a normalized absolute path. The
# normalization includes removing '.' and '..' components,
# removing duplicate slashes as well as any trailing slashes.
# If the specified path does not point to an existing file
# or directory, nothing is printed to stdout.
#
# Params:
#   $1:  path  the path to resolve
#
# Returns:
#   stdout: the resolved path if existing
_resolve_absolute_path() {
    local path="$1"

    if [ -e "${path}" ]; then
        local resolvedPath
        if [ -d "${path}" ]; then
            resolvedPath="$(cd "${path}" && pwd)"
        elif [ -e "${path}" ]; then
            local dir="${path%/*}"
            dir="$(cd "${dir:-"/"}" && pwd)"
            local file="${path##*/}"

            resolvedPath="${dir}/${file}"
        fi

        echo "${resolvedPath}"
    fi
}