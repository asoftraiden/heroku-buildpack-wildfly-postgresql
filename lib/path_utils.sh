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
        local dir="$(cd "${path%/*}" && pwd)"
        local file="${path##*/}"

        if [ -n "${file}" ]; then
            echo "${dir}/${file}"
        else
            echo "${dir}"
        fi
    fi
}