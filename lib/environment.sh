#!/usr/bin/env bash
#
# shellcheck disable=SC2155

export_env_dir() {
    local envDir="$1"
    local whitelist="${2:-""}"
    local blacklist="$(_env_blacklist "$3")"

    if [ -d "${envDir}" ]; then
        local envFile
        for envFile in "${envDir}"/*; do
            local varname="${envFile#${envDir}/}"
            if echo "${varname}" | grep -E "${whitelist}" | grep -Evq "${blacklist}"; then
                export "${varname}=$(cat "${envFile}")"
            fi
        done
    fi
}

# Usage: $ _env-blacklist pattern
# Outputs a regex of default blacklist env vars.
_env_blacklist() {
    local regex=${1:-''}
    if [ -n "$regex" ]; then
        regex="|$regex"
    fi
    echo "^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH$regex)$"
}