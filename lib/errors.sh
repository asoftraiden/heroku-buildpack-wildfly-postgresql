#!/usr/bin/env bash

# Writes a formatted error message provided on stdin to the standard
# output and exits with an status of 1. If no input is provided on the
# stdin channel the function produces an error itself.
#
# Input:
#   stdin:  the error message
#
# Returns
#   stdout: the resulting error message
#   exit code: 1
write_error() {
    if [ -t 0 ]; then
        error "Error message on stdin expected. Use a heredoc to write it."
    fi

    # We need to use the 'true' command here since 'read' exits with 1
    # when it encounters EOF. The delimiter is unset here so that 'read'
    # obtains the complete input including all lines and sets it to the
    # command variable. The 'true' command is important for scripts
    # using 'set -e' like the buildpack's compile script so that they
    # don't abort execution on the exit code 1 (see also
    # https://stackoverflow.com/a/15422165). The 'set -e' option is
    # responsible for exiting the shell if a command exits with a non-zero
    # exit status.
    local errorMessage
    read -r -d '' errorMessage || true

    error_return "${errorMessage}"
}

error_unsupported_postgresql_driver_version() {
    local version="$1"
    local defaultVersion="$2"

    write_error <<ERROR
Unsupported PostgreSQL Driver version: ${version}

Please ensure the specified version in 'postgresql.driver.version' in your
system.properties file is valid and one of those uploaded to Maven Central:
http://central.maven.org/maven2/org/postgresql/postgresql

You can also remove the property from your system.properties file to install
the default version ${defaultVersion}.
ERROR
}

error_postgresql_driver_name_not_set() {
    write_error <<ERROR
PostgreSQL driver name is not set

The PostgreSQL datasource depends on an existing driver installation.
Please ensure you have the PostgreSQL driver installed. You can also
manually set the name of the driver using the POSTGRESQL_DRIVER_NAME
config var.
ERROR
}

error_postgresql_driver_not_installed() {
    local driverName="$1"

    write_error <<ERROR
PostgreSQL driver is not installed: ${driverName}

The configured driver '${driverName}' is not installed at the WildFly
server. Ensure the PostgreSQL driver is correctly installed before
installing the datasource and that you are using the correct driver
name. You can also manually set the driver name with the
POSTGRESQL_DRIVER_NAME config var.
ERROR
}

error_invalid_hibernate_dialect_namespace() {
    local dialect="$1"
    local referenceUrl="$2"

    write_error <<ERROR
Invalid Hibernate dialect namespace: ${dialect}

The Hibernate dialect needs to begin with the 'org.hibernate.dialect'
namespace. For a complete list of dialects visit:
${referenceUrl}
ERROR
}

error_not_a_postgresql_dialect() {
    local dialect="$1"
    local referenceUrl="$2"

    write_error <<ERROR
Not a PostgreSQL dialect: ${dialect}

The requested Hibernate dialect is not applicable to PostgreSQL. As
this buildpack creates a datasource for connecting to a PostgreSQL
database the dialect is expected to be Postgres-compatible.

For a complete list of supported dialects visit
${referenceUrl}
ERROR
}

error_unsupported_hibernate_dialect() {
    local dialect="$1"
    local referenceUrl="$2"

    write_error <<ERROR
Unsupported Hibernate dialect: ${dialect}

The requested Hibernate dialect does not exist. Please verify that
you use one of the dialects defined at
${referenceUrl}
ERROR
}

error_jboss_home_not_set() {
    write_error <<ERROR
JBOSS_HOME not set or not existing

The JBOSS_HOME directory is not set correctly. Verify that you have an
existing WildFly installation under the '.jboss' directory. This can
be done either by the associated Heroku WildFly buildpack or by any
other external service installing a WildFly service to '.jboss'.

The associated buildpack is intended by this buildpack and the preferred
way of installation. For more information refer to the GitHub repository:
https://github.com/mortenterhart/heroku-buildpack-wildfly

An alternative way of setting JBOSS_HOME is to explicitly set a config
var with the path to the WildFly home directory for your application:

  heroku config:set JBOSS_HOME=path/to/wildfly-X.X.X.Final

This setting overrides the location set by this buildpack.
ERROR
}
