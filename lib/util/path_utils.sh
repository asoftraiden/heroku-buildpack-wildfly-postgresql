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