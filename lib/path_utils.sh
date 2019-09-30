#!/usr/bin/env bash
#
# shellcheck disable=SC2155

_is_relative_path() {
    local path="$1"

    ! [[ "${path}" =~ ^/ ]]
}

_resolve_absolute_path() {
    local path="$1"

    if [ -e "${path}" ]; then
        local dir="${path%/*}"
        dir="$(cd "${dir:-"/"}" && pwd)"
        local file="${path##*/}"

        local resolvedPath="${dir}"
        if [ -n "${file}" ]; then
            resolvedPath="${dir}/${file}"
        fi

        resolvedPath="$(shopt -s extglob; echo "${resolvedPath//\/*(\/)/\/}")"

        echo "${resolvedPath}"
    fi
}