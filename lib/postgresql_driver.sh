#!/usr/bin/env bash
#
# This script provides useful functionalities for the installation
# of the PostgreSQL JDBC driver at the WildFly server. The driver
# is downloaded in a customizable version and added to the server
# as a module before it is installed finally.
#
# The driver version can be configured using the property
# 'postgresql.driver.version' in the system.properties file. The
# specified version is validated so that the driver can be downloaded
# accordingly.
#
# The PostgreSQL driver name is defined during installation which
# is required for the datasource creation. It is stored in the
# POSTGRESQL_DRIVER_NAME environment variable which can also be
# used as a config var to set a custom driver name.
#
# The driver name and version are stored in environment variables
# and written to a .profile.d script which is read during dyno
# startup.
#
# This script uses a builtin dependency management. All dependent scripts
# and buildpacks are loaded and sourced at the beginning of this file to
# prevent overriding functions defined here.
#
# === Note for Buildpack creators ===
#
# When sourcing this script it is recommended to use 'set -e' to abort
# execution on any command exiting with a non-zero exit status so that
# execution will not continue on an error. The 'set -E' (note the uppercase
# 'E') option is also recommended for ERR traps to be active in functions
# called from other functions (subfunctions). This script uses an ERR
# trap to shutdown the WildFly server after an error.
#
# shellcheck disable=SC1090,SC2155

# ------------------------------------------
### DEFAULTS
# ------------------------------------------

DEFAULT_POSTGRESQL_DRIVER_NAME="postgresql"
DEFAULT_POSTGRESQL_DRIVER_VERSION="42.2.8"

# ------------------------------------------
### CONFIG VARS
# ------------------------------------------

export POSTGRESQL_DRIVER_NAME="${POSTGRESQL_DRIVER_NAME:-${DEFAULT_POSTGRESQL_DRIVER_NAME}}"

# ------------------------------------------
### DEPENDENCIES
# ------------------------------------------

# Loads the scripts from the lib/ directory and other buildpacks that
# this script depends on. The inherited functions are used throughout
# this and other scripts of this buildpack.
#
# Returns:
#   always 0
_load_script_dependencies() {
    # Get absolute path of script directory
    local scriptDir="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

    # Load dependent buildpacks
    source "${scriptDir}/vendor/load_buildpacks.sh"

    # Load output messages
    source "${scriptDir}/messages/debug.sh"
    source "${scriptDir}/messages/errors.sh"
    source "${scriptDir}/messages/warnings.sh"

    # Load utilities
    source "${scriptDir}/util/common.sh"
    source "${scriptDir}/util/path_utils.sh"

    # Load WildFly controls
    source "${scriptDir}/wildfly/wildfly_controls.sh"
}

# Load other script files and unset the function
_load_script_dependencies
unset -f _load_script_dependencies

# ------------------------------------------
### FUNCTIONS
# ------------------------------------------

# Installs the PostgreSQL JDBC driver to the WildFly server. The driver
# is downloaded and cached between builds and is added as a module to
# the running WildFly server. The driver is then installed as a JDBC
# driver to the server. The driver version can be configured by the
# 'postgresql.driver.version' property in the system.properties file.
# If not specified, the default version will be taken. The function
# also creates a .profile.d script for environment variables.
#
# Params:
#   $1:  buildDir  The Heroku build directory
#   $2:  cachedir  The Heroku cache directory
#
# Returns:
#   0: The driver was installed successfully
#   1: An unexpected error occurred
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

    # Resolve absolute paths of build and cache directories
    buildDir="$(_resolve_absolute_path "${buildDir}")" && debug_var "buildDir"
    cacheDir="$(_resolve_absolute_path "${cacheDir}")" && debug_var "cacheDir"

    # Detect the configured driver version
    local postgresqlVersion="${3:-$(detect_postgresql_driver_version "${buildDir}")}"
    debug_mmeasure "driver.version" "${postgresqlVersion}"

    local postgresqlDriverJar="postgresql-${postgresqlVersion}.jar"

    # Download the driver if not cached yet
    if [ ! -f "${cacheDir}/${postgresqlDriverJar}" ]; then
        download_postgresql_driver "${postgresqlVersion}" "${cacheDir}/${postgresqlDriverJar}"
    else
        status "Using PostgreSQL Driver ${postgresqlVersion} from cache"
    fi

    _load_wildfly_environment_variables "${buildDir}"

    _check_error_options_set
    _shutdown_on_error

    # Create the driver module and install the driver
    # at the WildFly server
    local moduleName="org.postgresql"
    _create_postgresql_driver_module "${moduleName}" "${cacheDir}/${postgresqlDriverJar}"
    _install_postgresql_jdbc_driver "${moduleName}" "${postgresqlVersion}"

    export POSTGRESQL_DRIVER_NAME="${POSTGRESQL_DRIVER_NAME:-${DEFAULT_POSTGRESQL_DRIVER_NAME}}" && debug_var "POSTGRESQL_DRIVER_NAME"
    export POSTGRESQL_DRIVER_VERSION="${postgresqlVersion}" && debug_var "POSTGRESQL_DRIVER_VERSION"

    _create_postgresql_driver_profile_script "${buildDir}"
}

# Creates a module for the PostgreSQL driver at the WildFly server for
# use with a JDBC driver resource.
#
# Params:
#   $1:  moduleName            the name of the new module
#   $2:  postgresqlDriverPath  path to the driver jar file
#
# Returns:
#   0: The module was created successfully
#   1: The module could not be created due to an error
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
    debug_mtime "driver.module.creation.time" "${start}"
}

# Installs the PostgreSQL JDBC driver to the WildFly server by creating
# a JDBC driver resource at the server. The driver module is required
# for the driver resource and needs to be supplied for the installation.
#
# Params:
#   $1:  moduleName         The name of the driver module
#   $2:  postgresqlVersion  The version of the PostgreSQL driver
#
# Returns:
#   0: The JDBC driver was installed successfully
#   1: The driver could not be installed due to an error
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
    debug_mtime "driver.installation.time" "${start}"
}

# Downloads the PostgreSQL JDBC driver in a specific version to a
# specified destination. The specified version is checked by
# validating the download url and the SHA-1 checksum is verified
# for the downloaded jar file.
#
# Params:
#   $1:  postgresqlVersion  the driver version to download
#   $2:  targetFilename     the file to write the driver to
#
# Returns:
#   0: The driver was downloaded and verified successfully
#   1: The specified version is invalid or the SHA-1 checksum
#      verification failed
download_postgresql_driver() {
    local postgresqlVersion="$1"
    local targetFilename="$2"

    local postgresqlDownloadUrl="$(_get_postgresql_driver_url "${postgresqlVersion}")"
    debug_mmeasure "driver.download.url" "${postgresqlDownloadUrl}"

    if ! validate_postgresql_driver_url "${postgresqlDownloadUrl}" "${postgresqlVersion}"; then
        mcount "driver.download.url.invalid"
        return 1
    fi

    local -i downloadStart="$(nowms)"
    status_pending "Downloading PostgreSQL JDBC Driver ${postgresqlVersion} to cache"
    curl --retry 3 --silent --location --output "${targetFilename}" "${postgresqlDownloadUrl}"
    status_done
    debug_mtime "driver.download.time" "${downloadStart}"

    status "Verifying SHA1 checksum"
    local postgresqlSHA1="$(curl --retry 3 --silent --location "${postgresqlDownloadUrl}.sha1")"
    if ! verify_sha1_checksum "${postgresqlSHA1}" "${targetFilename}"; then
        mcount "driver.sha1.verification.fail"
        return 1
    fi
    mcount "driver.sha1.verification.success"
}

# Verifies the SHA-1 checksum that is provided for the PostgreSQL driver file.
# The checksum needs to be downloaded first and can then be passed to this
# function in order to check it against the jar file.
#
# Params:
#   $1:  checksum  the SHA-1 checksum for the jar file
#   $2:  file      the path to the jar file
#
# Returns:
#   0: The checksum matches the jar file
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

# Detects the configured version for the PostgreSQL driver or chooses
# the default driver version if not configured. The version can be
# configured by the property 'postgresql.driver.version' in the
# system.properties file.
#
# Params:
#   $1:  buildDir  The Heroku build directory
#
# Returns:
#   stdout: the detected PostgreSQL driver version
#   0: The driver version was detected successfully
#   1: The build directory does not exist
detect_postgresql_driver_version() {
    local buildDir="$1"

    if [ ! -d "${buildDir}" ]; then
        # Redirect to stderr so that the error won't be captured
        # in command substitutions
        error_return "Failed to detect PostgreSQL Driver version: Build directory does not exist: ${buildDir}" >&2
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

# Validates the download url of the PostgreSQL driver by checking
# for the HTTP response code 200. If the download url returns a 404
# code the specified driver version does not exist.
#
# Params:
#   $1:  postgresqlUrl      the download url to validate
#   $2:  postgresqlVersion  the specified driver version
#
# Returns:
#   0: The download url points to an existing jar file
#   1: The specified driver version is undefined
validate_postgresql_driver_url() {
    local postgresqlUrl="$1"
    local postgresqlVersion="$2"

    if [ "$(_get_url_status "${postgresqlUrl}")" != "200" ]; then
        error_unsupported_postgresql_driver_version "${postgresqlVersion}" "${DEFAULT_POSTGRESQL_DRIVER_VERSION}"
        return 1
    fi
}

# Returns the download url for the PostgreSQL driver of a specific
# version.
#
# Params:
#   $1:  postgresqlVersion  the driver version to use
#
# Returns:
#   stdout: the PostgreSQL driver download url
_get_postgresql_driver_url() {
    local postgresqlVersion="$1"

    local postgresqlBaseUrl="http://central.maven.org/maven2/org/postgresql/postgresql"
    local postgresqlDownloadUrl="${postgresqlBaseUrl}/${postgresqlVersion}/postgresql-${postgresqlVersion}.jar"

    echo "${postgresqlDownloadUrl}"
}

# Creates a .profile.d script to load the environment variables
# for the PostgreSQL driver on application startup.
#
# Params:
#   $1:  buildDir  The Heroku build directory
#
# Returns:
#   exit code and a new .profile.d script
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
    mcount "driver.profile.script"
    debug_file "${profileScript}"
}