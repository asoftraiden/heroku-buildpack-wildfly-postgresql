#!/usr/bin/env bash
#
# shellcheck disable=SC1090,SC2155

# By default, read connection URL, username and password from environment
# variables provided by the Heroku Postgres Add-on
DEFAULT_DATASOURCE_JNDI_NAME="java:jboss/datasources/appDS"
DEFAULT_DATASOURCE_CONNECTION_URL="\${env.JDBC_DATABASE_URL:}"
DEFAULT_DATASOURCE_USERNAME="\${env.JDBC_DATABASE_USERNAME:}"
DEFAULT_DATASOURCE_PASSWORD="\${env.JDBC_DATABASE_PASSWORD:}"

DEFAULT_WAR_PERSISTENCE_XML_PATH="WEB-INF/classes/META-INF/persistence.xml"
DEFAULT_HIBERNATE_DIALECT="org.hibernate.dialect.PostgreSQL95Dialect"

export HIBERNATE_DIALECT="${HIBERNATE_DIALECT:-${DEFAULT_HIBERNATE_DIALECT}}"
export HIBERNATE_DIALECT_AUTO_UPDATE="${HIBERNATE_DIALECT_AUTO_UPDATE:-"true"}"
export WAR_PERSISTENCE_XML_PATH="${WAR_PERSISTENCE_XML_PATH:-${DEFAULT_WAR_PERSISTENCE_XML_PATH}}"
export SKIP_DATASOURCE="${SKIP_DATASOURCE:-"false"}"

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
    source "${scriptDir}/persistence/hibernate_dialect.sh"
    source "${scriptDir}/util/path_utils.sh"
    source "${scriptDir}/util/war_utils.sh"

    # Load WildFly controls
    source "${scriptDir}/wildfly/wildfly_controls.sh"
}

# Load other script files and unset the function
_load_script_dependencies
unset -f _load_script_dependencies

# Installs the PostgreSQL datasource to the WildFly server. The
# connection url, username and password may be supplied as arguments,
# but are read from the environment variables JDBC_DATABASE_URL,
# JDBC_DATABASE_USERNAME and JDBC_DATABASE_PASSWORD inherited from
# the Heroku Postgres Add-on by default. The datasource installation
# requires an existing WildFly installation. The datasource name and
# JNDI name are read from the persistence.xml residing in one of the
# deployed WAR files. Finally, the WildFly server will be shutdown.
#
# The datasource installation is skipped if the SKIP_DATASOURCE
# config var is set to 'true'. The installation fails if the
# PostgreSQL driver has not been installed before.
#
# Params:
#   $1:  buildDir       the Heroku build directory
#   $2:  connectionUrl  (optional) the connection url of the datasource
#   $3:  username       (optional) the username for the database
#   $4:  password       (optional) the password for the database
#
# Returns:
#   0: The datasource installation was successfully or has been
#      skipped.
#   1: The installation failed with an error.
install_postgresql_datasource() {
    if _skip_datasource_enabled; then
        notice "Skipping installation of PostgreSQL datasource because the SKIP_DATASOURCE config var has been set to 'true'"
        return
    fi

    local buildDir="$1"
    if [ ! -d "${buildDir}" ]; then
        error_return "Failed to install PostgreSQL Datasource: Build directory does not exist: ${buildDir}"
        return 1
    fi

    buildDir="$(_resolve_absolute_path "${buildDir}")" && debug_var "buildDir"

    local connectionUrl="${2:-${DEFAULT_DATASOURCE_CONNECTION_URL}}"
    local username="${3:-${DEFAULT_DATASOURCE_USERNAME}}"
    local password="${4:-${DEFAULT_DATASOURCE_PASSWORD}}"

    _load_wildfly_environment_variables "${buildDir}"

    _check_error_options_set
    _shutdown_on_error

    _verify_postgresql_driver_installation

    local -i identifyStart="$(nowms)"

    if [ -z "${DATASOURCE_JNDI_NAME}" ] || [ -z "${DATASOURCE_NAME}" ]; then
        identify_and_update_persistence_unit
    fi
    debug_mtime "datasource.identify.persistence-unit.time" "${identifyStart}"

    notice "Using following parameters for datasource
  Datasource Name: ${DATASOURCE_NAME}
  Datasource JNDI Name: ${DATASOURCE_JNDI_NAME}
  PostgreSQL Driver Name: ${POSTGRESQL_DRIVER_NAME}"

    local -i datasourceCreationStart="$(nowms)"
    _execute_jboss_command "Creating PostgreSQL Datasource" <<COMMAND
data-source add
    --name=${DATASOURCE_NAME}
    --jndi-name=${DATASOURCE_JNDI_NAME}
    --user-name=${username}
    --password=${password}
    --driver-name=${POSTGRESQL_DRIVER_NAME}
    --connection-url=${connectionUrl}
    --max-pool-size=25
    --blocking-timeout-wait-millis=5000
    --enabled=true
    --jta=true
    --use-ccm=false
    --valid-connection-checker-class-name=org.jboss.jca.adapters.jdbc.extensions.postgres.PostgreSQLValidConnectionChecker
    --background-validation=true
    --exception-sorter-class-name=org.jboss.jca.adapters.jdbc.extensions.postgres.PostgreSQLExceptionSorter
COMMAND
    debug_mtime "datasource.creation.time" "${datasourceCreationStart}"

    export POSTGRESQL_DATASOURCE_NAME="${DATASOURCE_NAME}" && debug_var "POSTGRESQL_DATASOURCE_NAME"
    export POSTGRESQL_DATASOURCE_JNDI_NAME="${DATASOURCE_JNDI_NAME}" && debug_var "POSTGRESQL_DATASOURCE_JNDI_NAME"

    _create_postgresql_datasource_profile_script "${buildDir}"

    _shutdown_wildfly_server
    mcount "wildfly.shutdown"
}

# Locates and updates the persistence unit of the deployed application.
# The first found persistence unit in one of the deployed WAR files is
# taken and extracted to obtain the datasource JNDI name. The datasource
# name is created by the last component of the JNDI name. If the
# DATASOURCE_JNDI_NAME or DATASOURCE_NAME config vars are set their
# values are preferred over those coming from the persistence unit.
#
# If no persistence unit is found a warning is printed to stdout and
# default values for the JNDI and datasource names will be used.
#
# The functions returns its identified names in the DATASOURCE_NAME
# and DATASOURCE_JNDI_NAME environment variables.
#
# Additionally, the persistence unit is scanned after a configured
# Hibernate dialect that has the form
#
#   <property name="hibernate.dialect" value="<dialect>"/>
#
# In case a Hibernate dialect is detected it is updated with the value
# of the HIBERNATE_DIALECT config var which also has a default value.
# The dialect is only updated if the HIBERNATE_DIALECT_AUTO_UPDATE
# config var is set to 'true' which is the default. Afterwards the
# persistence unit in the corresponding WAR file is updated with the
# new persistence file.
#
# Finally, the WAR file contains an updated persistence unit with the
# configured dialect compatible to PostgreSQL databases. The WAR file
# is deployed to the WildFly server on startup.
#
# Note: The persistence unit is located inside the WAR file by means of
# an assumed WAR path. This is 'WEB-INF/classes/META-INF/persistence.xml'
# by default. If this path exists in any of the deployed WAR files the
# file is extracted from the WAR file and taken as persistence unit. The
# WAR path can be configured using the WAR_PERSISTENCE_XML_PATH config var.
#
# Config Vars:
#   The execution can be customized using these config vars:
#
#   DATASOURCE_NAME:                the datasource name (overrides detected name)
#   DATASOURCE_JNDI_NAME:           the datasource JNDI name (overrides detected name)
#   HIBERNATE_DIALECT:              the Hibernate dialect to configure
#   HIBERNATE_DIALECT_AUTO_UPDATE:  whether to update the Hibernate dialect or not
#   JBOSS_HOME:                     the path to a WildFly installation
#   WAR_PERSISTENCE_XML_PATH:       the path to the persistence.xml file inside the
#                                   WAR file (relative to the root of the WAR file)
#
# Returns:
#   0: The datasource and JNDI names were identified and the Hibernate
#      dialect was updated if configured.
#   1: The persistence file could not be extracted, the Hibernate dialect
#      could not be updated or the WAR file could not be updated.
identify_and_update_persistence_unit() {
    local datasourceJNDIName="${DATASOURCE_JNDI_NAME:-${DEFAULT_DATASOURCE_JNDI_NAME}}"
    local datasourceName="${DATASOURCE_NAME:-${DEFAULT_DATASOURCE_JNDI_NAME##*/}}"

    local warFile="$(_find_war_with_persistence_unit "${WAR_PERSISTENCE_XML_PATH}" "${JBOSS_HOME}")"

    if [ -n "${warFile}" ] && [ -f "${warFile}" ]; then
        status "Found Persistence Unit in persistence.xml of deployment '${warFile##*/}'"
        local deploymentsTempDir="$(mktemp -d "/tmp/deployments.XXXXXX")"

        debug_command "unzip -d \"${deploymentsTempDir}\" -q \"${warFile}\" \"${WAR_PERSISTENCE_XML_PATH}\""
        unzip -d "${deploymentsTempDir}" -q "${warFile}" "${WAR_PERSISTENCE_XML_PATH}"
        local persistenceFile="${deploymentsTempDir}/${WAR_PERSISTENCE_XML_PATH}" && debug_var "persistenceFile"
        mcount "persistence.unit.extracted"

        datasourceJNDIName="${DATASOURCE_JNDI_NAME:-$(_get_datasource_jndi_name "${persistenceFile}")}" && debug_var "datasourceJNDIName"
        datasourceName="${DATASOURCE_NAME:-${datasourceJNDIName##*/}}" && debug_var "datasourceName"

        if _hibernate_dialect_auto_update_enabled && [ -f "${persistenceFile}" ]; then
            debug_mmeasure "hibernate.dialect.auto-update" "enabled"
            debug_mmeasure "hibernate.dialect.class" "${HIBERNATE_DIALECT}"

            update_hibernate_dialect "${persistenceFile}" "${HIBERNATE_DIALECT}"
            update_file_in_war "${warFile}" "${deploymentsTempDir}" "${WAR_PERSISTENCE_XML_PATH}"
        else
            notice_inline "Auto-updating of Hibernate dialect is disabled"
            debug_mmeasure "hibernate.dialect.auto-update" "disabled"
        fi

        rm -rf "${deploymentsTempDir}"
    else
        warning_no_persistence_unit_found "${WAR_PERSISTENCE_XML_PATH}"
        mcount "no.persistence.unit.found"
    fi

    export DATASOURCE_JNDI_NAME="${datasourceJNDIName}"
    export DATASOURCE_NAME="${datasourceName}"

    debug_mmeasure "datasource.name" "${datasourceName}"
    debug_mmeasure "datasource.jndi.name" "${datasourceJNDIName}"
}

# Verifies that the PostgreSQL driver is installed at the WildFly
# server because it is required for the creation of the datasource.
# If the driver name is not set or the driver not installed, an
# error will be returned on stdout.
#
# Returns:
#   0: The PostgreSQL driver is installed correctly.
#   1: The driver name is not set or the driver has not been
#      installed at the WildFly server.
_verify_postgresql_driver_installation() {
    if ! _is_wildfly_running; then
        _start_wildfly_server
        _wait_until_wildfly_running
    fi

    status "Verifying PostgreSQL driver installation"

    if [ -z "${POSTGRESQL_DRIVER_NAME}" ]; then
        error_postgresql_driver_name_not_set
        mcount "driver.verification.fail"
        return 1
    fi

    _execute_jboss_command_pipable <<COMMAND | tee >((indent && echo) >&2) |
/subsystem=datasources/jdbc-driver=postgresql:read-attribute(
    name=driver-name
)
COMMAND
    grep -q "\"result\" => \"${POSTGRESQL_DRIVER_NAME}\"" || {
        error_postgresql_driver_not_installed "${POSTGRESQL_DRIVER_NAME}"
        mcount "driver.verification.fail"
        return 1
    }

    mcount "driver.verification.successful"
}

# Checks whether the SKIP_DATASOURCE config var has been set to 'true'
# or not. This has the effect that the datasource creation is skipped.
# If the config var is set to an invalid value, a warning is printed
# to stdout and the default value will be assigned. Defaults to 'false'.
#
# Returns:
#   0: The option is enabled
#   1: The option is disabled
_skip_datasource_enabled() {
    case "${SKIP_DATASOURCE}" in
        true)   return 0 ;;
        false)  return 1 ;;
        *)
            warning_config_var_invalid_boolean_value "SKIP_DATASOURCE" "false"
            export SKIP_DATASOURCE="false"
            return 1
            ;;
    esac
}

# Checks whether the HIBERNATE_DIALECT_AUTO_UPDATE config var has been
# set to 'true' or not. This has the effect of enabling the automatic
# update of the Hibernate dialect if configured in the persistence unit.
# If the config var is set to an invalid value, a warning is printed to
# stdout and the default value will be assigned. Defaults to 'true'.
#
# Returns:
#   0: The option is enabled
#   1: The option is disabled
_hibernate_dialect_auto_update_enabled() {
    case "${HIBERNATE_DIALECT_AUTO_UPDATE}" in
        true)   return 0 ;;
        false)  return 1 ;;
        *)
            warning_config_var_invalid_boolean_value "HIBERNATE_DIALECT_AUTO_UPDATE" "true"
            export HIBERNATE_DIALECT_AUTO_UPDATE="true"
            return 0
            ;;
    esac
}

# Parses the datasource JNDI name from a persistence.xml file and
# returns it on stdout. A default value for the JNDI name will be
# used if the persistence file does't exist or it doesn't define
# a JNDI name.
#
# Params:
#   $1:  persistenceFile  the path to the persistence file
#
# Returns:
#   stdout: the datasource JNDI name
_get_datasource_jndi_name() {
    local persistenceFile="$1"

    if [ -f "${persistenceFile}" ]; then
        local jndiName="$(grep -Eo '<jta-data-source>[A-Za-z0-9/:-]+</jta-data-source>' "${persistenceFile}" | \
            sed -E 's#^<jta-data-source>|</jta-data-source>$##g')"
        if [ -n "${jndiName}" ]; then
            echo "${jndiName}"
        else
            echo "${DEFAULT_DATASOURCE_JNDI_NAME}"
        fi
    else
        echo "${DEFAULT_DATASOURCE_JNDI_NAME}"
    fi
}

# Creates a .profile.d script to load the environment variables
# for the PostgreSQL datasource on startup. The .profile.d
# directory is created if not existing.
#
# Params:
#   $1:  buildDir  The Heroku build directory
#
# Returns:
#   always 0
_create_postgresql_datasource_profile_script() {
    local buildDir="$1"
    local profileScript="${buildDir}/.profile.d/wildfly-postgresql.sh"

    mkdir -p "${buildDir}/.profile.d"
    status_pending "Creating .profile.d script for PostgreSQL Datasource"
    cat >> "${profileScript}" <<SCRIPT
# Environment variables for the PostgreSQL Datasource
export POSTGRESQL_DATASOURCE_NAME="${POSTGRESQL_DATASOURCE_NAME}"
export POSTGRESQL_DATASOURCE_JNDI_NAME="${POSTGRESQL_DATASOURCE_JNDI_NAME}"
SCRIPT
    status_done
    mcount "datasource.profile.script"
    debug_file "${profileScript}"
}
