#!/usr/bin/env bash
#
# shellcheck disable=SC1090,SC2155

DEFAULT_POSTGRESQL_DRIVER_NAME="postgresql"
DEFAULT_POSTGRESQL_DRIVER_VERSION="42.2.8"

DEFAULT_WAR_PERSISTENCE_XML_PATH="WEB-INF/classes/META-INF/persistence.xml"
DEFAULT_HIBERNATE_DIALECT="org.hibernate.dialect.PostgreSQL95Dialect"

DEFAULT_DATASOURCE_JNDI_NAME="java:jboss/datasources/appDS"
DEFAULT_DATASOURCE_CONNECTION_URL="\${env.JDBC_DATABASE_URL}"
DEFAULT_DATASOURCE_USERNAME="\${env.JDBC_DATABASE_USERNAME}"
DEFAULT_DATASOURCE_PASSWORD="\${env.JDBC_DATABASE_PASSWORD}"

_load_heroku_wildfly_buildpack() {
    local herokuWildflyBuildpackUrl="https://github.com/mortenterhart/heroku-buildpack-wildfly.git"
    local herokuWildflyBuildpackDir="/tmp/heroku-wildfly-buildpack"

    if [ ! -d "${herokuWildflyBuildpackDir}" ]; then
        git clone --quiet "${herokuWildflyBuildpackUrl}" "${herokuWildflyBuildpackDir}"
    fi

    source "${herokuWildflyBuildpackDir}/lib/wildfly_utils.sh"
}

# Load WildFly buildpack at the beginning to prevent overriding of equally
# named functions defined here
_load_heroku_wildfly_buildpack

install_postgresql_driver() {
    local buildDir="$1"
    local cacheDir="$2"
    if [ ! -d "${buildDir}" ]; then
        error_return "Could not install PostgreSQL Driver: Build directory does not exist"
        return 1
    fi
    if [ ! -d "${cacheDir}" ]; then
        error_return "Could not install PostgreSQL Driver: Cache directory does not exist"
        return 1
    fi

    local postgresqlVersion="${3:-$(detect_postgresql_driver_version "${buildDir}")}"

    local postgresqlDriverJar="postgresql-${postgresqlVersion}.jar"

    if [ ! -f "${cacheDir}/${postgresqlDriverJar}" ]; then
        download_postgresql_driver "${postgresqlVersion}" "${cacheDir}/${postgresqlDriverJar}"
    else
        status "Using PostgreSQL Driver ${postgresqlVersion} from cache"
    fi

    _load_wildfly_environment_variables "${buildDir}"

    local moduleName="org.postgresql"
    _create_postgresql_driver_module "${moduleName}" "${cacheDir}/${postgresqlDriverJar}"
    _install_postgresql_jdbc_driver "${moduleName}"

    export POSTGRESQL_DRIVER_NAME="${POSTGRESQL_DRIVER_NAME:-${DEFAULT_POSTGRESQL_DRIVER_NAME}}"
    export POSTGRESQL_DRIVER_VERSION="${postgresqlVersion}"

    _create_postgresql_driver_profile_script "${buildDir}"
}

_create_postgresql_driver_module() {
    local moduleName="$1"
    local postgresqlDriverPath="$2"

    _execute_jboss_command "Creating PostgreSQL Driver module" <<COMMAND
module add
    --name=${moduleName}
    --resources=${postgresqlDriverPath}
    --dependencies=javax.api,javax.transaction.api
COMMAND
}

_install_postgresql_jdbc_driver() {
    local moduleName="$1"

    export POSTGRESQL_DRIVER_NAME="${POSTGRESQL_DRIVER_NAME:-${DEFAULT_POSTGRESQL_DRIVER_NAME}}"

    _execute_jboss_command "Installing PostgreSQL JDBC Driver ${postgresqlVersion}" <<COMMAND
/subsystem=datasources/jdbc-driver=postgresql:add(
    driver-name=${POSTGRESQL_DRIVER_NAME},
    driver-module-name=${moduleName},
    driver-xa-datasource-class-name=org.postgresql.xa.PGXADataSource
)
COMMAND
}

download_postgresql_driver() {
    local postgresqlVersion="$1"
    local targetFilename="$2"

    local postgresqlDownloadUrl="$(_get_postgresql_driver_url "${postgresqlVersion}")"

    if ! validate_postgresql_url "${postgresqlDownloadUrl}" "${postgresqlVersion}"; then
        return 1
    fi

    status_pending "Downloading PostgreSQL JDBC Driver ${postgresqlVersion} to cache"
    curl --retry 3 --silent --location --output "${targetFilename}" "${postgresqlDownloadUrl}"
    status_done

    status "Verifying SHA1 checksum"
    local postgresqlSHA1="$(curl --retry 3 --silent --location "${postgresqlDownloadUrl}.sha1")"
    if ! verify_sha1_checksum "${postgresqlSHA1}" "${targetFilename}"; then
        return 1
    fi
}

detect_postgresql_driver_version() {
    local buildDir="$1"

    if [ ! -d "${buildDir}" ]; then
        error_return "Could not detect PostgreSQL Driver version: Build directory does not exist" >&2
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

install_postgresql_datasource() {
    # Config var ONLY_INSTALL_DRIVER
    if [ -n "${ONLY_INSTALL_DRIVER}" ] && [ "${ONLY_INSTALL_DRIVER}" == "true" ]; then
        return
    fi

    local buildDir="$1"
    if [ ! -d "${buildDir}" ]; then
        error_return "Could not install PostgreSQL Datasource: Build directory does not exist"
        return 1
    fi

    local datasourceConnectionUrl="${2:-${DEFAULT_DATASOURCE_CONNECTION_URL}}"
    local username="${3:-${DEFAULT_DATASOURCE_USERNAME}}"
    local password="${4:-${DEFAULT_DATASOURCE_PASSWORD}}"

    _load_wildfly_environment_variables "${buildDir}"

    local warFile="$(_find_war_with_persistence_file "${WAR_PERSISTENCE_XML_PATH}")"
    local deploymentsTempDir="$(mktemp -d "/tmp/deployments.XXXXXX")"
    local persistenceFile="$(_extract_persistence_file_from_war "${warFile}" "${WAR_PERSISTENCE_XML_PATH}" "${deploymentsTempDir}")"

    local datasourceJNDIName="${DATASOURCE_JNDI_NAME:-$(_get_datasource_jndi_name "${persistenceFile}")}"
    local datasourceName="${DATASOURCE_NAME:-${datasourceJNDIName##*/}}"

    if [ "${DISABLE_HIBERNATE_AUTO_UPDATE}" != "true" ] && \
       [ -f "${persistenceFile}" ]; then
        update_hibernate_dialect "${persistenceFile}" "${HIBERNATE_DIALECT:-${DEFAULT_HIBERNATE_DIALECT}}"
        _update_file_in_war "${warFile}" "${deploymentsTempDir}" "${WAR_PERSISTENCE_XML_PATH}"
    fi

    rm -rf "${deploymentsTempDir}"

    _execute_jboss_command "Creating PostgreSQL Datasource" <<COMMAND
data-source add
    --name=${datasourceName}
    --jndi-name=${datasourceJNDIName}
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

    export POSTGRESQL_DATASOURCE_NAME="${datasourceName}"
    export POSTGRESQL_DATASOURCE_JNDI_NAME="${datasourceJNDIName}"

    _create_postgresql_datasource_profile_script "${buildDir}"

    _shutdown_wildfly_server
}

_find_war_with_persistence_file() {
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

_extract_persistence_file_from_war() {
    local warFile="$1"
    local persistenceFilePath="$2"
    local targetDir="$3"

    echo "Extracting persistence.xml"
    echo "warFile: $warFile"
    echo "persistenceFilePath: $persistenceFilePath"
    echo "targetDir: $targetDir"

    if _war_file_contains_file "${warFile}" "${persistenceFilePath}"; then
        unzip -d "${targetDir}" -q "${warFile}" "${persistenceFilePath}"
        echo "${targetDir}/${persistenceFilePath}"
    fi
}

_war_file_contains_file() {
    local zipFile="$1"
    local file="$2"

    unzip -q -l "${zipFile}" "${file}" >/dev/null
}

update_hibernate_dialect() {
    local persistenceFile="$1"
    local dialect="$2"

    if [ ! -f "${persistenceFile}" ]; then
        error_return "Passed persistence.xml file does not exist"
        return 1
    fi

    if ! validate_hibernate_dialect "${dialect}"; then
        return 1
    fi

    if grep -Eq '<property [[:blank:]]*name="hibernate\.dialect"' "${persistenceFile}"; then
        sed -Ei "s#org\.hibernate\.dialect\.[A-Za-z0-9]+Dialect#${dialect}#" "${persistenceFile}"
    fi
}

_update_file_in_war() {
    local warFile="$1"
    local rootPath="$2"
    local relativeFile="$3"

    if [ ! -d "${rootPath}" ]; then
        error_return "Root path needs to be a directory"
        return 1
    fi

    if [ ! -f "${rootPath}/${relativeFile}" ]; then
        error_return "Relative file does not exist under root path"
        return 1
    fi

    if _is_relative_path "${warFile}"; then
        warFile="$(_resolve_absolute_path "${warFile}")"
    fi

    (cd "${rootPath}" && zip -q --update "${warFile}" "${relativeFile}")
}

_is_relative_path() {
    local path="$1"

    ! [[ "${path}" =~ ^/ ]]
}

_resolve_absolute_path() {
    local path="$1"

    if [ -e "${path}" ]; then
        local dir="$(cd "${path%/*}" && pwd)"
        local file="${path##*/}"

        if [ -n "${file}" ]; then
            echo "${dir}/${file}"
        else
            echo "${dir}"
        fi
    fi
}

validate_hibernate_dialect() {
    local dialect="$1"

    local hibernateDocsBaseUrl="https://docs.jboss.org/hibernate/orm/current/javadocs"
    local referenceUrl="${hibernateDocsBaseUrl}/org/hibernate/dialect/package-summary.html"

    if ! [[ "${dialect}" =~ ^org\.hibernate\.dialect ]]; then
        error_return "Invalid Hibernate dialect namespace: ${dialect}

The Hibernate dialect needs to begin with the 'org.hibernate.dialect'
namespace. For a complete list of dialects visit
${referenceUrl}"
        return 1
    fi

    if ! [[ "${dialect}" =~ PostgreSQL[8-9]?[0-5]?Dialect$ ]]; then
        error_return "Not a PostgreSQL dialect: ${dialect}

The requested Hibernate dialect is not applicable to PostgreSQL. As
this buildpack creates a datasource for connecting to a PostgreSQL
database the dialect is expected to be Postgres-compatible.

For a complete list of supported dialects visit
${referenceUrl}"
        return 1
    fi

    local docsUrl="${hibernateDocsBaseUrl}/${dialect//.//}.html"
    if [ "$(_get_url_status "${docsUrl}")" != "200" ]; then
        error_return "Unsupported Hibernate dialect: ${dialect}

The requested Hibernate dialect does not exist. Please verify that
you use one of the dialects defined at
${referenceUrl}"
        return 1
    fi
}

validate_postgresql_url() {
    local postgresqlUrl="$1"
    local postgresqlVersion="$2"

    if [ "$(_get_url_status "${postgresqlUrl}")" != "200" ]; then
        error_return "Unsupported PostgreSQL Driver version: ${postgresqlVersion}

Please ensure the specified version in 'postgresql.driver.version' in your
system.properties file is valid and one of those uploaded to Maven Central:
http://central.maven.org/maven2/org/postgresql/postgresql

You can also remove the property from your system.properties file to install
the default version ${DEFAULT_POSTGRESQL_DRIVER_VERSION}."
        return 1
    fi
}

_execute_jboss_command() {
    local statusMessage="$1"

    if [ -t 0 ]; then
        error_return "JBoss command on stdin expected. Use a heredoc to specify it."
        return 1
    fi

    # We need to use the 'true' command here since 'read' exits with 1
    # if it doesn't find the delimiter which is usually '\n'. This is
    # very important for scripts using 'set -e' like the buildpack's
    # compile script so that they don't abort execution (see also
    # https://stackoverflow.com/questions/15421331/reading-a-bash-variable-from-a-multiline-here-document).
    #
    # The delimiter is unset here so that 'read' obtains the complete
    # input including all lines and sets it to the command variable.
    local command
    read -r -d '' command || true

    if ! _is_wildfly_running; then
        _start_wildfly_server
        _wait_until_wildfly_running
        status "WildFly is running"
    fi

    [ -n "${statusMessage}" ] && status "${statusMessage}..."

    "${JBOSS_CLI}" --connect --command="${command}" | indent
}

_start_wildfly_server() {
    status "Starting WildFly server..."
    "${JBOSS_HOME}/bin/standalone.sh" --admin-only | indent &
}

_wait_until_wildfly_running() {
    until _is_wildfly_running; do
        sleep 1
    done
}

_is_wildfly_running() {
    "${JBOSS_CLI}" --connect --command=":read-attribute(name=server-state)" 2>/dev/null | grep -q "running"
}

_shutdown_wildfly_server() {
    status "Shutdown WildFly server"
    "${JBOSS_CLI}" --connect --command=":shutdown" | indent
}

_get_postgresql_driver_url() {
    local postgresqlVersion="$1"

    local postgresqlBaseUrl="http://central.maven.org/maven2/org/postgresql/postgresql"
    local postgresqlDownloadUrl="${postgresqlBaseUrl}/${postgresqlVersion}/postgresql-${postgresqlVersion}.jar"

    echo "${postgresqlDownloadUrl}"
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

_create_postgresql_driver_profile_script() {
    local buildDir="$1"
    local profileScript="${buildDir}/.profile.d/wildfly-postgresql.sh"

    if [ -d "${buildDir}/.profile.d" ]; then
        status_pending "Creating .profile.d script for PostgreSQL driver"
        cat >> "${profileScript}" <<SCRIPT
# Environment variables for the PostgreSQL Driver
export POSTGRESQL_DRIVER_VERSION="${POSTGRESQL_DRIVER_VERSION}"
export POSTGRESQL_DRIVER_NAME="${POSTGRESQL_DRIVER_NAME}"
SCRIPT
        status_done
    fi
}

_create_postgresql_datasource_profile_script() {
    local buildDir="$1"
    local profileScript="${buildDir}/.profile.d/wildfly-postgresql.sh"

    if [ -d "${buildDir}/.profile.d" ]; then
        status_pending "Creating .profile.d script for PostgreSQL Datasource"
        cat >> "${profileScript}" <<SCRIPT
# Environment variables for the PostgreSQL Datasource
export POSTGRESQL_DATASOURCE_NAME="${POSTGRESQL_DATASOURCE_NAME}"
export POSTGRESQL_DATASOURCE_JNDI_NAME="${POSTGRESQL_DATASOURCE_JNDI_NAME}"
SCRIPT
        status_done
    fi
}

_load_wildfly_environment_variables() {
    local buildDir="$1"

    # First look after the .profile.d script of the Heroku Wildfly
    # buildpack and source it if existing
    local wildflyBuildpackScript="${buildDir}/.profile.d/wildfly.sh"
    if [ -f "${wildflyBuildpackScript}" ] && grep -q "^export JBOSS_HOME=" "${wildflyBuildpackScript}"; then
        source "${wildflyBuildpackScript}"
    fi

    if [ -d "${buildDir}/.jboss" ]; then
        # Expand the Wildfly directory with a glob to get the directory name
        # and version
        local wildflyDir=("${buildDir}"/.jboss/wildfly-*)
        if [ "${#wildflyDir[@]}" -eq 1 ] && [ -d "${wildflyDir[0]}" ]; then
            export JBOSS_HOME="${JBOSS_HOME:-"${wildflyDir[0]}"}"
            export JBOSS_CLI="${JBOSS_CLI:-"${JBOSS_HOME}/bin/jboss-cli.sh"}"
            export WILDFLY_VERSION="${WILDFLY_VERSION:-"${JBOSS_HOME#*wildfly-}"}"
        fi
    fi

    if [ -z "${JBOSS_HOME}" ] || [ ! -d "${JBOSS_HOME}" ]; then
        error_return "JBOSS_HOME not set or not existing

The JBOSS_HOME directory is not set correctly. Verify that you have an
existing WildFly installation under the '.jboss' directory. This can
be done either by the associated Heroku WildFly buildpack or by any
other external service installing a WildFly service to '.jboss'.

The associated buildpack is intended by this buildpack and the preferred
way of installation. For more information refer to the GitHub repository:
https://github.com/mortenterhart/heroku-buildpack-wildfly

An alternative way of setting JBOSS_HOME is to explicitly set a config
var with the path to the WildFly home directory for your application:

  heroku config:set JBOSS_HOME=path/to/wildfly-16.0.0.Final

This setting overrides the location set by this buildpack."
        return 1
    fi

    # Config variable CUSTOM_WAR_PERSISTENCE_XML_PATH
    export WAR_PERSISTENCE_XML_PATH="${WAR_PERSISTENCE_XML_CUSTOM_PATH:-${DEFAULT_WAR_PERSISTENCE_XML_PATH}}"
}
