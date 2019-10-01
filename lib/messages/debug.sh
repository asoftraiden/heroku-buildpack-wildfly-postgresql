#!/usr/bin/env bash
#
# shellcheck disable=SC2155

export BUILDPACK_DEBUG="${BUILDPACK_DEBUG:-"false"}"

# Prints a formatted debug message if debug mode is enabled. All
# lines are indented following the Heroku output style.
#
# Params:
#   $*:  message  the debug message
#
# Returns:
#   stdout: the formatted debug message
debug() {
    if _debug_enabled; then
        echo " #     DEBUG: $*" | indent no_first_line_indent
    fi
}

# Prints a formatted debug message detached from other output if
# debug mode is enabled.
#
# Params:
#   $*:  message  the debug message
#
# Returns:
#   stdout: the detached debug message
debug_detached() {
    if _debug_enabled; then
        echo
        debug "$*"
        echo
    fi
}

# Prints an arbitrary command that is executed as a debug message
# detached from other output. The message is only printed if the
# debug mode is enabled.
#
# Params:
#   $*:  command  the executed command and its arguments
#
# Returns:
#   stdout: the debug message with the command
debug_command() {
    if _debug_enabled; then
        local command="$*"

        debug_detached "Executing following command: $*"
    fi
}

# Prints an arbitrary JBoss command executed with the JBoss CLI
# as a debug message detached from other output. The message is
# only printed if the debug mode is enabled. The username, password
# and connection URL in the command that creates a new datasource
# will be concealed from the output.
#
# Params:
#   $*:  command  the JBoss command
#
# Returns:
#   stdout: the debug message with the JBoss command
debug_jboss_command() {
    if _debug_enabled; then
        local command="$*"

        echo
        debug "Executing following JBoss command:"
        echo "${command}" | _debug_hide_credentials | indent_num 9
        echo
    fi
}

# Prints the value of a variable as a debug message if debug mode
# is enabled.
#
# Params:
#   $1:  varname  the name of the variable
#
# Returns:
#   stdout: the name and value of the variable
debug_var() {
    if _debug_enabled; then
        local varname="$1"

        debug "${varname}=${!varname}"
    fi
}

# Prints the contents of a file as a debug message if debug mode
# is enabled.
#
# Params:
#    $1:  file  the filename
#
# Returns:
#   stdout: the filename and contents of the file
debug_file() {
    if _debug_enabled; then
        local file="$1"

        echo
        debug "Contents of File ${file}:"
        indent_num 9 < "${file}"
        echo
    fi
}

# Prints a time measure of a specific build step as a debug
# message if debug mode is enabled. The measure is identified
# by a key and has a value in milliseconds, i.e. the precision
# is 3 decimal places. In addition, the time measure is written
# to the buildpack log file.
#
# Params:
#   $1:  key    the identifier for the measure
#   $2:  start  the start time of the build step (in ms)
#
# Usage:
#   local start="$(nowms)"
#   curl -sLO https://download.jboss.org/wildfly/16.0.0.Final/wildfly-16.0.0.Final.zip
#   debug_mtime "wildfly.download.time" "${start}"
#
# Returns:
#   stdout: the time measurement
debug_mtime() {
    local key="$1"
    local start="$2"

    if _debug_enabled; then
        local end="$(nowms)"
        debug_detached "Time Measure: $(awk '{ printf "%s = %.3f s\n", $1, ($3 - $2) / 1000; }' <<< "${key} ${start} ${end}")"
    fi

    mtime "${key}" "${start}"
}

# Prints an arbitrary measure of a specific build step as a
# debug message if debug mode is enabled. The measure is
# identified by a key and has an arbitrary value. In addition,
# the measure is written to the buildpack log file.
#
# Params:
#   $1:  key    the identifier of the measure
#   $2:  value  the value of the measurement
#
# Returns:
#   stdout: the measurement
debug_mmeasure() {
    local key="$1"
    local value="$2"

    if _debug_enabled; then
        debug "Measure: ${key}=${value}"
    fi

    mmeasure "${key}" "${value}"
}

# Checks if the debug mode is enabled or disabled.
#
# Returns:
#   0: The debug mode is enabled
#   1: The debug mode is disabled
_debug_enabled() {
    [ "${BUILDPACK_DEBUG}" == "true" ]
}

# Hides the username, password and connection URL of the
# datasource creation command by replacing the values to
# the options with '*****'. This prevents those values
# from being output to the console and the logs. The
# connection URL is hidden because it may also contain
# a username or password or a sensitive hostname. However,
# it does not prevent other sensitive information from
# being written to the console.
#
# Input:
#   stdin:  the raw datasource command with sensitive
#           information
#
# Returns:
#   stdout: the datasource command with hidden credentials
_debug_hide_credentials() {
    sed -E 's/(--user-name|--password|--connection-url)=.*$/\1=*****/g'
}

# Indents an output message by a certain number of spaces.
# The message can be either the output of a command, a file
# or a code block.
#
# Params:
#   $1:  numSpaces  (optional) the number of spaces (default 2)
#
# Input:
#   stdin:  the output message
#
# Returns:
#   stdout: the indented output message
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

# Checks the value of the BUILDPACK_DEBUG config var for
# validity. If the value is invalid, a warning is printed
# to the console and the default value is adopted instead.
_check_debug_config_var_value() {
    case "${BUILDPACK_DEBUG}" in
        true | false) ;;
        *)
            warning_config_var_invalid_boolean_value "BUILDPACK_DEBUG" "false"
            export BUILDPACK_DEBUG="false"
    esac
}

# Check the BUILDPACK_DEBUG value when sourcing
_check_debug_config_var_value
