#!/usr/bin/env bash
#
# shellcheck disable=SC2155

# Exports the config vars in the environment directory ENV_DIR as
# environment variables. Heroku creates a file for each defined
# config var in ENV_DIR with the filename being the variable name
# and the contents being the value of the variable. However, some
# variables like $PATH, $GIT_DIR or $CPATH can cause conflicts
# with other programs when exported. Therefore these variables can
# be defined on the blacklist not to get exported. On the other
# hand the whitelist contains variables that are exported
# explicitly.
#
# Params:
#   $1:  envDir     The Heroku directory for config vars
#   $2:  whitelist  (optional) A list of variables to export explicitly
#   $3:  blacklist  (optional) A list of variables not to export
#
# Returns:
#   exit status 0
export_env_dir() {
    local envDir="$1"
    local whitelist="${2:-""}"
    local blacklist="$(_env_blacklist "$3")"

    if [ -d "${envDir}" ]; then
        local envFile
        for envFile in "${envDir}"/*; do
            if [ -f "${envFile}" ]; then
                local varname="${envFile#${envDir}/}"
                if echo "${varname}" | grep -E "${whitelist}" | grep -Evq "${blacklist}"; then
                    export "${varname}=$(cat "${envFile}")"
                fi
            fi
        done
    fi
}

# Builds a grep regex for blacklisting default environment variables.
# Additional variables can be added with the regex parameter.
#
# Params:
#   $1:  regex  (optional) Custom regex for blacklisting environment
#               variables
#
# Returns:
#   stdout: the resulting regex
_env_blacklist() {
    local regex=${1:-''}
    if [ -n "$regex" ]; then
        regex="|$regex"
    fi
    echo "^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH$regex)$"
}