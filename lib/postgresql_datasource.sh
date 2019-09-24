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
export HIBERNATE_AUTO_UPDATE="${HIBERNATE_AUTO_UPDATE:-"true"}"
export WAR_PERSISTENCE_XML_PATH="${WAR_PERSISTENCE_XML_PATH:-${DEFAULT_WAR_PERSISTENCE_XML_PATH}}"
export ONLY_INSTALL_DRIVER="${ONLY_INSTALL_DRIVER:-"false"}"

install_postgresql_datasource() {
    if _only_install_driver; then
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

    _check_errexit_set
    _shutdown_on_error

    _verify_postgresql_driver_installation

    local datasourceJNDIName="${DATASOURCE_JNDI_NAME:-${DEFAULT_DATASOURCE_JNDI_NAME}}"
    local datasourceName="${DATASOURCE_NAME:-${DEFAULT_DATASOURCE_JNDI_NAME##*/}}"

    if [ -z "${DATASOURCE_JNDI_NAME}" ] || [ -z "${DATASOURCE_NAME}" ]; then
        local warFile="$(_find_war_with_persistence_unit "${WAR_PERSISTENCE_XML_PATH}")"

        if [ -n "${warFile}" ] && [ -f "${warFile}" ]; then
            status "Found Persistence Unit in persistence.xml of deployment '${warFile##*/}'"
            local deploymentsTempDir="$(mktemp -d "/tmp/deployments.XXXXXX")"

            unzip -d "${deploymentsTempDir}" -q "${warFile}" "${WAR_PERSISTENCE_XML_PATH}"
            local persistenceFile="${deploymentsTempDir}/${WAR_PERSISTENCE_XML_PATH}"

            datasourceJNDIName="${DATASOURCE_JNDI_NAME:-$(_get_datasource_jndi_name "${persistenceFile}")}"
            datasourceName="${DATASOURCE_NAME:-${datasourceJNDIName##*/}}"

            if _hibernate_auto_update_enabled && [ -f "${persistenceFile}" ]; then
                update_hibernate_dialect "${persistenceFile}" "${HIBERNATE_DIALECT:-${DEFAULT_HIBERNATE_DIALECT}}"
                update_file_in_war "${warFile}" "${deploymentsTempDir}" "${WAR_PERSISTENCE_XML_PATH}"
            else
                notice_inline "Auto-updating of Hibernate dialect is disabled"
            fi

            rm -rf "${deploymentsTempDir}"
        else
            warning "No Persistence Unit found in any WAR file. Database connections will not be possible.

The buildpack looks for a persistence.xml definition at the path
'${WAR_PERSISTENCE_XML_PATH}' in all deployed WAR files.
The path can be altered by setting the WAR_PERSISTENCE_XML_PATH
config var which overrides the default value:

  heroku config:set WAR_PERSISTENCE_XML_PATH=path/in/war

Ensure that your path is relative to the root of the WAR archive."
        fi
    fi

    DATASOURCE_JNDI_NAME="${datasourceJNDIName}"
    DATASOURCE_NAME="${datasourceName}"

    notice "Using following parameters for datasource
  Datasource Name: ${DATASOURCE_NAME}
  Datasource JNDI Name: ${DATASOURCE_JNDI_NAME}
  PostgreSQL Driver Name: ${POSTGRESQL_DRIVER_NAME}"

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

    export POSTGRESQL_DATASOURCE_NAME="${DATASOURCE_NAME}"
    export POSTGRESQL_DATASOURCE_JNDI_NAME="${DATASOURCE_JNDI_NAME}"

    _create_postgresql_datasource_profile_script "${buildDir}"

    _shutdown_wildfly_server
}

_verify_postgresql_driver_installation() {
    if ! _is_wildfly_running; then
        _start_wildfly_server
        _wait_until_wildfly_running
    fi

    status "Verifying PostgreSQL driver installation"

    if [ -z "${POSTGRESQL_DRIVER_NAME}" ]; then
        error_return "PostgreSQL driver name is not set

The PostgreSQL datasource depends on an existing driver installation.
Please ensure you have the PostgreSQL driver installed. You can also
manually set the name of the driver using the POSTGRESQL_DRIVER_NAME
config var."
        return 1
    fi

    local tty="$(tty)"
    _execute_jboss_command_pipable <<COMMAND | tee >(indent > "${tty}") |
/subsystem=datasources/jdbc-driver=postgresql:read-attribute(
    name=driver-name
)
COMMAND
    grep -q "\"result\" => \"${POSTGRESQL_DRIVER_NAME}\"" || {
        error_return "PostgreSQL driver is not installed: ${POSTGRESQL_DRIVER_NAME}

The configured driver '${POSTGRESQL_DRIVER_NAME}' is not installed
at the WildFly server. Ensure the PostgreSQL driver is correctly
installed before installing the datasource and that you are using
the correct driver name. You can also manually set the driver name
with the POSTGRESQL_DRIVER_NAME config var."
        return 1
    }
}

_find_war_with_persistence_unit() {
    local persistenceFilePath="$1"

    # Return at first match
    local warFile
    for warFile in "${JBOSS_HOME}"/standalone/deployments/*.war; do
        if _war_file_contains_file "${warFile}" "${persistenceFilePath}"; then
            echo "${warFile}"
            return
        fi
    done
}

_war_file_contains_file() {
    local zipFile="$1"
    local file="$2"

    if [ ! -f "${zipFile}" ]; then
        return 1
    fi

    unzip -q -l "${zipFile}" "${file}" >/dev/null
}

_only_install_driver_enabled() {
    case "${ONLY_INSTALL_DRIVER}" in
        true)   return 0 ;;
        false)  return 1 ;;
        *)
            warning "Invalid value for ONLY_INSTALL_DRIVER config var: '${ONLY_INSTALL_DRIVER}'
Valid values include 'true' and 'false'. Using default value 'false'."
            ONLY_INSTALL_DRIVER="false"
            return 1
            ;;
    esac
}

_hibernate_auto_update_enabled() {
    case "${HIBERNATE_AUTO_UPDATE}" in
        true)   return 0 ;;
        false)  return 1 ;;
        *)
            warning "Invalid value for HIBERNATE_AUTO_UPDATE config var: '${HIBERNATE_AUTO_UPDATE}'
Valid values include 'true' and 'false'. Using default value 'true'."
            HIBERNATE_AUTO_UPDATE="true"
            return 0
            ;;
    esac
}

update_file_in_war() {
    local warFile="$1"
    local rootPath="$2"
    local relativeFile="$3"

    if [ ! -d "${rootPath}" ]; then
        error_return "Root path needs to be a directory: ${rootPath}"
        return 1
    fi

    if [ ! -f "${rootPath}/${relativeFile}" ]; then
        error_return "Relative file does not exist under root path: ${relativeFile}"
        return 1
    fi

    if _is_relative_path "${warFile}"; then
        warFile="$(_resolve_absolute_path "${warFile}")"
    fi

    status "Patching '${warFile##*/}' with updated persistence.xml"

    (cd "${rootPath}" && zip -q --update "${warFile}" "${relativeFile}")
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

}
