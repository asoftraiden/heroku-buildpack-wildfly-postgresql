#!/usr/bin/env bash
#
# shellcheck disable=SC1090,SC2155

DEFAULT_POSTGRESQL_DRIVER_NAME="postgresql"
DEFAULT_POSTGRESQL_DRIVER_VERSION="42.2.8"

export POSTGRESQL_DRIVER_NAME="${POSTGRESQL_DRIVER_NAME:-${DEFAULT_POSTGRESQL_DRIVER_NAME}}"

_load_script_dependencies() {
    # Get absolute path of script directory
    local scriptDir="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

    # Load dependent buildpacks
    source "${scriptDir}/load_buildpacks.sh"

    source "${scriptDir}/common.sh"
    source "${scriptDir}/errors.sh"

    source "${scriptDir}/wildfly_controls.sh"
}

_load_script_dependencies
unset -f _load_script_dependencies

install_postgresql_driver() {
    local buildDir="$1"
    local cacheDir="$2"
    if [ ! -d "${buildDir}" ]; then
        error_return "Failed to install PostgreSQL Driver: Build directory does not exist: ${buildDir}"
        return 1
    fi
    if [ ! -d "${cacheDir}" ]; then
        error_return "Failed to install PostgreSQL Driver: Cache directory does not exist: ${cacheDir}"
        return 1
    fi

    local postgresqlVersion="${3:-$(detect_postgresql_driver_version "${buildDir}")}"
    mcount "driver.version" "${postgresqlVersion}"

    local postgresqlDriverJar="postgresql-${postgresqlVersion}.jar"

    if [ ! -f "${cacheDir}/${postgresqlDriverJar}" ]; then
        download_postgresql_driver "${postgresqlVersion}" "${cacheDir}/${postgresqlDriverJar}"
    else
        status "Using PostgreSQL Driver ${postgresqlVersion} from cache"
    fi

    _load_wildfly_environment_variables "${buildDir}"

    _check_error_options_set
    _shutdown_on_error

    local moduleName="org.postgresql"
    _create_postgresql_driver_module "${moduleName}" "${cacheDir}/${postgresqlDriverJar}"
    _install_postgresql_jdbc_driver "${moduleName}" "${postgresqlVersion}"

    export POSTGRESQL_DRIVER_NAME="${POSTGRESQL_DRIVER_NAME:-${DEFAULT_POSTGRESQL_DRIVER_NAME}}"
    export POSTGRESQL_DRIVER_VERSION="${postgresqlVersion}"

    _create_postgresql_driver_profile_script "${buildDir}"
}

_create_postgresql_driver_module() {
    local moduleName="$1"
    local postgresqlDriverPath="$2"

    local -i start="$(nowms)"
    _execute_jboss_command "Creating PostgreSQL Driver module '${moduleName}'" <<COMMAND
module add
    --name=${moduleName}
    --resources=${postgresqlDriverPath}
    --dependencies=javax.api,javax.transaction.api
COMMAND
    mtime "driver.module.creation.time" "${start}"
}

_install_postgresql_jdbc_driver() {
    local moduleName="$1"
    local postgresqlVersion="$2"

    local -i start="$(nowms)"
    _execute_jboss_command "Installing PostgreSQL JDBC Driver ${postgresqlVersion}" <<COMMAND
/subsystem=datasources/jdbc-driver=postgresql:add(
    driver-name=${POSTGRESQL_DRIVER_NAME},
    driver-module-name=${moduleName},
    driver-xa-datasource-class-name=org.postgresql.xa.PGXADataSource
)
COMMAND
    mtime "driver.installation.time" "${start}"
}

download_postgresql_driver() {
    local postgresqlVersion="$1"
    local targetFilename="$2"

    local postgresqlDownloadUrl="$(_get_postgresql_driver_url "${postgresqlVersion}")"
    mcount "driver.download.url" "${postgresqlDownloadUrl}"

    if ! validate_postgresql_driver_url "${postgresqlDownloadUrl}" "${postgresqlVersion}"; then
        return 1
    fi

    local -i downloadStart="$(nowms)"
    status_pending "Downloading PostgreSQL JDBC Driver ${postgresqlVersion} to cache"
    curl --retry 3 --silent --location --output "${targetFilename}" "${postgresqlDownloadUrl}"
    status_done
    mtime "driver.download.time" "${downloadStart}"

    status "Verifying SHA1 checksum"
    local postgresqlSHA1="$(curl --retry 3 --silent --location "${postgresqlDownloadUrl}.sha1")"
    if ! verify_sha1_checksum "${postgresqlSHA1}" "${targetFilename}"; then
        return 1
    fi
}

# Verifies the SHA-1 checksum that is provided for the WildFly zip file. The
# checksum needs to be downloaded from the WildFly download page and can be
# passed to this function in order to check it against the zip file.
#
# Params:
#   $1:  checksum  the downloaded SHA-1 checksum for the zip file
#   $2:  file      the path to the zip file
#
# Returns:
#   0: The checksum matches the zip file
#   1: The checksum is invalid
verify_sha1_checksum() {
    local checksum="$1"
    local file="$2"

    if ! echo "${checksum} ${file}" | sha1sum --check --strict --quiet; then
        error_return "SHA1 checksum verification failed for ${file}"
        return 1
    fi

    return 0
}

detect_postgresql_driver_version() {
    local buildDir="$1"

    if [ ! -d "${buildDir}" ]; then
        error_return "Failed to detect PostgreSQL Driver version: Build directory does not exist: ${buildDir}"
        return 1
    fi

    local systemProperties="${buildDir}/system.properties"
    if [ -f "${systemProperties}" ]; then
        local detectedVersion="$(get_app_system_property "${systemProperties}" "postgresql.driver.version")"
        if [ -n "${detectedVersion}" ]; then
            echo "${detectedVersion}"
        else
            echo "${DEFAULT_POSTGRESQL_DRIVER_VERSION}"
        fi
    else
        echo "${DEFAULT_POSTGRESQL_DRIVER_VERSION}"
    fi
}

validate_postgresql_driver_url() {
    local postgresqlUrl="$1"
    local postgresqlVersion="$2"

    if [ "$(_get_url_status "${postgresqlUrl}")" != "200" ]; then
        error_unsupported_postgresql_driver_version "${postgresqlVersion}" "${DEFAULT_POSTGRESQL_DRIVER_VERSION}"
        return 1
    fi
}

_get_postgresql_driver_url() {
    local postgresqlVersion="$1"

    local postgresqlBaseUrl="http://central.maven.org/maven2/org/postgresql/postgresql"
    local postgresqlDownloadUrl="${postgresqlBaseUrl}/${postgresqlVersion}/postgresql-${postgresqlVersion}.jar"

    echo "${postgresqlDownloadUrl}"
}

_create_postgresql_driver_profile_script() {
    local buildDir="$1"
    local profileScript="${buildDir}/.profile.d/wildfly-postgresql.sh"

    status_pending "Creating .profile.d script for PostgreSQL driver"
    mkdir -p "${buildDir}/.profile.d"
    cat >> "${profileScript}" <<SCRIPT
# Environment variables for the PostgreSQL Driver
export POSTGRESQL_DRIVER_VERSION="${POSTGRESQL_DRIVER_VERSION}"
export POSTGRESQL_DRIVER_NAME="${POSTGRESQL_DRIVER_NAME}"
SCRIPT
    status_done
}