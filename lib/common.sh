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

# Returns the HTTP status code for the specified url. All other output from
# curl is discarded. This can be used to check the validity of urls, for
# example the WildFly download url.
#
# Params:
#   $1:  url  the url for which to get the status code
#
# Returns:
#   stdout: the HTTP status code
_get_url_status() {
    local url="$1"

    curl --retry 3 --silent --head --write-out "%{http_code}" --output /dev/null --location "${url}"
}
