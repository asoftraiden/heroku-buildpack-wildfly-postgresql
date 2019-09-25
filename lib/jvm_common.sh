#!/usr/bin/env bash
#
# shellcheck disable=SC1090

# Downloads the JVM Common Buildpack if not already existing and sources the
# utility functions used throughout this script such as 'indent', 'error_return'
# and 'status'.
#
# Returns:
#   always 0
_load_jvm_common_buildpack() {
    local JVM_COMMON_BUILDPACK_URL="${JVM_COMMON_BUILDPACK_URL:-"https://buildpack-registry.s3.amazonaws.com/buildpacks/heroku/jvm.tgz"}"

    local jvmCommonDir="/tmp/jvm-common"
    if [ ! -d "${jvmCommonDir}" ]; then
        mkdir -p "${jvmCommonDir}"
        curl --retry 3 --silent --location "${JVM_COMMON_BUILDPACK_URL}" | tar xzm -C "${jvmCommonDir}" --strip-components=1
    fi

    source "${jvmCommonDir}/bin/util"
}

# Load the JVM Common buildpack
_load_jvm_common_buildpack