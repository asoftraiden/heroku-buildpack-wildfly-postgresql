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
export ONLY_INSTALL_DRIVER="${ONLY_INSTALL_DRIVER:-"false"}"

_load_script_dependencies() {
    # Get absolute path of script directory
    local scriptDir="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

    # Load dependent buildpacks
    source "${scriptDir}/load_buildpacks.sh"

    source "${scriptDir}/common.sh"
    source "${scriptDir}/errors.sh"
    source "${scriptDir}/warnings.sh"

    source "${scriptDir}/hibernate_dialect.sh"
    source "${scriptDir}/path_utils.sh"
    source "${scriptDir}/war_utils.sh"
    source "${scriptDir}/wildfly_controls.sh"
}

_load_script_dependencies
unset -f _load_script_dependencies

install_postgresql_datasource() {
    if _only_install_driver_enabled; then
        notice "Not installing PostgreSQL datasource because the ONLY_INSTALL_DRIVER config var has been set to 'true'"
        return
    fi

    local buildDir="$1"
    if [ ! -d "${buildDir}" ]; then
        error_return "Failed to install PostgreSQL Datasource: Build directory does not exist: ${buildDir}"
        return 1
    fi

    local datasourceConnectionUrl="${2:-${DEFAULT_DATASOURCE_CONNECTION_URL}}"
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
    mtime "datasource.identify.persistence-unit.time" "${identifyStart}"

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
    --connection-url=${datasourceConnectionUrl}
    --max-pool-size=25
    --blocking-timeout-wait-millis=5000
    --enabled=true
    --jta=true
    --use-ccm=false
    --valid-connection-checker-class-name=org.jboss.jca.adapters.jdbc.extensions.postgres.PostgreSQLValidConnectionChecker
    --background-validation=true
    --exception-sorter-class-name=org.jboss.jca.adapters.jdbc.extensions.postgres.PostgreSQLExceptionSorter
COMMAND
    mtime "datasource.creation.time" "${datasourceCreationStart}"

    export POSTGRESQL_DATASOURCE_NAME="${DATASOURCE_NAME}"
    export POSTGRESQL_DATASOURCE_JNDI_NAME="${DATASOURCE_JNDI_NAME}"

    _create_postgresql_datasource_profile_script "${buildDir}"

    _shutdown_wildfly_server
    mcount "wildfly.shutdown"
}

identify_and_update_persistence_unit() {
    local datasourceJNDIName="${DATASOURCE_JNDI_NAME:-${DEFAULT_DATASOURCE_JNDI_NAME}}"
    local datasourceName="${DATASOURCE_NAME:-${DEFAULT_DATASOURCE_JNDI_NAME##*/}}"

    local warFile="$(_find_war_with_persistence_unit "${WAR_PERSISTENCE_XML_PATH}")"

    if [ -n "${warFile}" ] && [ -f "${warFile}" ]; then
        status "Found Persistence Unit in persistence.xml of deployment '${warFile##*/}'"
        local deploymentsTempDir="$(mktemp -d "/tmp/deployments.XXXXXX")"

        unzip -d "${deploymentsTempDir}" -q "${warFile}" "${WAR_PERSISTENCE_XML_PATH}"
        local persistenceFile="${deploymentsTempDir}/${WAR_PERSISTENCE_XML_PATH}"
        mcount "persistence.unit.extracted"

        datasourceJNDIName="${DATASOURCE_JNDI_NAME:-$(_get_datasource_jndi_name "${persistenceFile}")}"
        datasourceName="${DATASOURCE_NAME:-${datasourceJNDIName##*/}}"

        if _hibernate_dialect_auto_update_enabled && [ -f "${persistenceFile}" ]; then
            update_hibernate_dialect "${persistenceFile}" "${HIBERNATE_DIALECT}"
            update_file_in_war "${warFile}" "${deploymentsTempDir}" "${WAR_PERSISTENCE_XML_PATH}"

            mmeasure "hibernate.dialect.update" "${HIBERNATE_DIALECT}"
        else
            notice_inline "Auto-updating of Hibernate dialect is disabled"
            mcount "hibernate.dialect.update.disabled"
        fi

        rm -rf "${deploymentsTempDir}"
    else
        warning_no_persistence_unit_found "${WAR_PERSISTENCE_XML_PATH}"
        mcount "no.persistence.unit.found"
    fi

    export DATASOURCE_JNDI_NAME="${datasourceJNDIName}"
    export DATASOURCE_NAME="${datasourceName}"

    mmeasure "datasource.name" "${datasourceName}"
    mmeasure "datasource.jndi.name" "${datasourceJNDIName}"
}

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

    local tty="$(tty)"
    _execute_jboss_command_pipable <<COMMAND | tee >(indent > "${tty}") |
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

_only_install_driver_enabled() {
    case "${ONLY_INSTALL_DRIVER}" in
        true)   return 0 ;;
        false)  return 1 ;;
        *)
            warning_config_var_invalid_boolean_value "ONLY_INSTALL_DRIVER" "false"
            ONLY_INSTALL_DRIVER="false"
            return 1
            ;;
    esac
}

_hibernate_dialect_auto_update_enabled() {
    case "${HIBERNATE_DIALECT_AUTO_UPDATE}" in
        true)   return 0 ;;
        false)  return 1 ;;
        *)
            warning_config_var_invalid_boolean_value "HIBERNATE_DIALECT_AUTO_UPDATE" "true"
            HIBERNATE_DIALECT_AUTO_UPDATE="true"
            return 0
            ;;
    esac
}

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
}
