#!/usr/bin/env bash
#
# shellcheck disable=SC1090,SC2155

# Do not pipe the output of this command as it might start a background
# process to start the WildFly server.
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
    fi

    [ -n "${statusMessage}" ] && status "${statusMessage}..."

    "${JBOSS_CLI}" --connect --command="${command}" | indent
    local exitStatus="${PIPESTATUS[0]}"

    if [ "${exitStatus}" -ne 0 ]; then
        error_return "JBoss command failed with exit code ${exitStatus}"
    fi

    return "${exitStatus}"
}

_execute_jboss_command_pipable() {
    if [ -t 0 ]; then
        error_return "JBoss command on stdin expected. Use a heredoc to specify it."
        return 1
    fi

    local command
    read -r -d '' command || true

    "${JBOSS_CLI}" --connect --command="${command}"
    local exitStatus="$?"

    if [ "${exitStatus}" -ne 0 ]; then
        error_return "JBoss command failed with exit code ${exitStatus}" >&2
    fi

    return "${exitStatus}"
}

_start_wildfly_server() {
    status "Starting WildFly server..."
    "${JBOSS_HOME}/bin/standalone.sh" --admin-only | indent &
}

_wait_until_wildfly_running() {
    until _is_wildfly_running; do
        sleep 1
    done
    status "WildFly is running"
}

_is_wildfly_running() {
    "${JBOSS_CLI}" --connect --command=":read-attribute(name=server-state)" 2>/dev/null | grep -q "running"
}

_shutdown_wildfly_server() {
    if _is_wildfly_running; then
        status "Shutdown WildFly server"
        "${JBOSS_CLI}" --connect --command=":shutdown" | indent && echo
    fi
}

_shutdown_on_error() {
    trap '_shutdown_wildfly_server; exit 1' ERR
}

_load_wildfly_environment_variables() {
    local buildDir="$1"

    if [ -d "${buildDir}/.jboss" ] && [ -z "${JBOSS_HOME}" ]; then
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

  heroku config:set JBOSS_HOME=path/to/wildfly-X.X.X.Final

This setting overrides the location set by this buildpack."
        return 1
    fi
}