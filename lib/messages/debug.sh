#!/usr/bin/env bash
#
# shellcheck disable=SC2155

export BUILDPACK_DEBUG="${BUILDPACK_DEBUG:-"false"}"

debug() {
    if _debug_enabled; then
        echo " #     DEBUG: $*" | indent no_first_line_indent
    fi
}

debug_detached() {
    if _debug_enabled; then
        echo
        debug "$*"
        echo
    fi
}

debug_command() {
    if _debug_enabled; then
        local command="$*"

        debug_detached "Executing following command: $*"
    fi
}

debug_jboss_command() {
    if _debug_enabled; then
        local command="$*"

        echo
        debug "Executing following JBoss command:"
        echo "${command}" | _debug_hide_credentials | indent_num 9
        echo
    fi
}

debug_var() {
    if _debug_enabled; then
        local varname="$1"

        debug "${varname}=${!varname}"
    fi
}

debug_file() {
    if _debug_enabled; then
        local file="$1"

        echo
        debug "Contents of File ${file}:"
        indent_num 9 < "${file}"
        echo
    fi
}

debug_mtime() {
    local key="$1"
    local start="$2"

    if _debug_enabled; then
        local end="$(nowms)"
        debug_detached "Time Measure: $(awk '{ printf "%s = %.3f s\n", $1, ($3 - $2) / 1000; }' <<< "${key} ${start} ${end}")"
    fi

    mtime "${key}" "${start}"
}

debug_mmeasure() {
    local key="$1"
    local value="$2"

    if _debug_enabled; then
        debug "Measure: ${key}=${value}"
    fi

    mmeasure "${key}" "${value}"
}

_debug_enabled() {
    [ "${DEBUG}" == "true" ]
}

_debug_hide_credentials() {
    sed -E 's/(--user-name|--password|--connection-url)=.*$/\1=*****/g'
}

indent_num() {
    local numSpaces="${1:-2}"

    local indent="" i
    for (( i = 0; i < numSpaces; i++ )); do
        indent+=" "
    done

    case "$(uname)" in
        Darwin) sed -l "s/^/${indent}/";;
        *)      sed -u "s/^/${indent}/";;
    esac
}

_check_debug_config_var_value() {
    case "${BUILDPACK_DEBUG}" in
        true | false) ;;
        *)
            warning_config_var_invalid_boolean_value "BUILDPACK_DEBUG" "false"
            export DEBUG="false"
    esac
}

_check_debug_config_var_value
