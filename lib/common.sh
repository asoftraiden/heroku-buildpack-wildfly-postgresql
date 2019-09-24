#!/usr/bin/env bash

_check_errexit_set() {
    if ! shopt -qo "errexit"; then
        warning "'errexit' option not set

You should use 'set -e' in your script as this buildpack relies
on error handling by exit status. Without it the build continues
on errors and may cause undesired results."
    fi
}

# Reads a system property from a properties file and outputs its value.
# Outputs nothing if the given property name is not defined or the file
# does not exist. The file and property arguments are required. They cause
# an error if they were not defined.
#
# Params:
#   $1:  file      the properties file
#   $2:  property  the name of the property
#
# Returns:
#   stdout: the value of the property if existing or nothing
get_app_system_property() {
    local file="${1?"No file specified"}"
    local property="${2?"No property specified"}"

    # Escape property for regex
    local escaped_property="${property//./\\.}"

    if [ -f "${file}" ]; then
        # Remove comments and print property value
        sed -E '/^[[:blank:]]*\#/d' "${file}" | \
        grep -E "^[[:blank:]]*${escaped_property}[[:blank:]]*=" | \
        sed -E "s/[[:blank:]]*${escaped_property}[[:blank:]]*=[[:blank:]]*//"
    fi
}
