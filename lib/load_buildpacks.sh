#!/usr/bin/env bash
#
# shellcheck disable=SC1090

JVM_COMMON_BUILDPACK_URL="${JVM_COMMON_BUILDPACK_URL:-"https://buildpack-registry.s3.amazonaws.com/buildpacks/heroku/jvm.tgz"}"
BUILDPACK_STDLIB_URL="${BUILDPACK_STDLIB_URL:-"https://lang-common.s3.amazonaws.com/buildpack-stdlib/v8/stdlib.sh"}"

# Downloads the JVM Common Buildpack if not already existing and sources the
# utility functions used throughout this script such as 'indent', 'error_return'
# and 'status'.
#
# Returns:
#   always 0
_load_jvm_common_buildpack() {
    local jvmCommonDir="/tmp/jvm-common"
    if [ ! -d "${jvmCommonDir}" ]; then
        mkdir -p "${jvmCommonDir}"
        curl --retry 3 --silent --location "${JVM_COMMON_BUILDPACK_URL}" | tar xzm -C "${jvmCommonDir}" --strip-components=1
    fi

    source "${jvmCommonDir}/bin/util"
}

_load_buildpack_stdlib() {
    local stdlibFile="/tmp/stdlib-v8.sh"
    if [ ! -f "${stdlibFile}" ]; then
        curl --retry 3 --silent --location --output "${stdlibFile}" "${BUILDPACK_STDLIB_URL}"
    fi

    source "${stdlibFile}"
}

# Load the JVM Common and Stdlib buildpacks
_load_jvm_common_buildpack
_load_buildpack_stdlib