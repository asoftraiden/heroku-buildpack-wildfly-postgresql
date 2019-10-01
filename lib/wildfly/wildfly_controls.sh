#!/usr/bin/env bash
#
# shellcheck disable=SC1090,SC2155

# Executes an arbitrary JBoss command read from stdin at the WildFly
# application server. If the server hasn't started yet it will be
# started automatically. An optional status message can be supplied
# to be printed before the actual command is executed. The exit status
# of the JBoss command is captured and returned as the exit status
# of this function, i.e. the build fails if any JBoss command fails.
#
# Note that this function is not suitable to be piped or redirected
# to another process because it starts the WildFly server as a
# background process and so the pipe won't terminate. If you want
# to capture the output of a JBoss command, use the
# '_execute_jboss_command_pipable' function below instead.
#
# Warning: The function requires the JBOSS_CLI environment variable
#          to be set correctly.
#
# Params:
#   $1:  statusMessage  (optional) a status message describing the
#                       command that is printed to stdout
#
# Input:
#   stdin:  The JBoss command (can be provided in a here document)
#
# Returns:
#   stdout: The command output, status message and potential errors
#   0: The command exited successfully
#   1: The command failed
_execute_jboss_command() {
    local statusMessage="$1"

    if [ -t 0 ]; then
        error_return "JBoss command on stdin expected. Use a heredoc to specify it."
        return 1
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
    local command
    read -r -d '' command || true

    if ! _is_wildfly_running; then
        _start_wildfly_server
        _wait_until_wildfly_running
    fi

    [ -n "${statusMessage}" ] && status "${statusMessage}..."

    debug_jboss_command "${command}"

    "${JBOSS_CLI}" --connect --command="${command}" | indent
    local exitStatus="${PIPESTATUS[0]}"

    if [ "${exitStatus}" -ne 0 ]; then
        error_return "JBoss command failed with exit code ${exitStatus}"
    fi

    return "${exitStatus}"
}

# Executes an arbitrary JBoss command read from stdin at the WildFly
# application server. Ensure that the server is running before using
# this function as it does not start the WildFly server automatically.
# The output can be safely piped or redirected to another process in
# order to process it. Error and debug messages are written to the
# stderr channel to avoid concealing errors and redirecting those
# messages along with the stdout channel.
#
# The exit status of the JBoss command is captured and returned as
# the exit status of this function, i.e. the build fails if any JBoss
# command fails.
#
# Warning: The function requires the JBOSS_CLI environment variable
#          to be set correctly.
#
# Input:
#   stdin:  The JBoss command (can be provided in a here document)
#
# Returns:
#   stdout: The command output and potential errors
#   0: The command exited successfully
#   1: The command failed
#
# Example:
#
#   # Check if the PostgreSQL driver is installed
#   _execute_jboss_command_pipable <<COMMAND | grep '"outcome" => "success"'
#   /subsystem=datasources/jdbc-driver=postgresql:read-attribute(
#       name=driver-name
#   )
#   COMMAND
#
_execute_jboss_command_pipable() {
    if [ -t 0 ]; then
        # Redirect error message to stderr to enable piping stdout
        # to another process
        error_return "JBoss command on stdin expected. Use a heredoc to specify it." >&2
        return 1
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
    local command
    read -r -d '' command || true

    # Redirect debug message to stderr to enable piping stdout to
    # another process
    debug_jboss_command "${command}" >&2

    "${JBOSS_CLI}" --connect --command="${command}"
    local exitStatus="$?"

    if [ "${exitStatus}" -ne 0 ]; then
        # Redirect error message to stderr to enable piping stdout
        # to another process
        error_return "JBoss command failed with exit code ${exitStatus}" >&2
    fi

    return "${exitStatus}"
}

# Starts the WildFly server in the admin-only mode as a background
# process. In the admin-only mode the server only opens its
# administrative interfaces in order to handle management requests
# such as JBoss commands. However, the HTTP and HTTPS services
# are not going to be started and so the application will not be
# deployed in this phase.
#
# Warning: The function requires the JBOSS_HOME environment variable
#          to be set correctly.
#
# Returns:
#   always 0
_start_wildfly_server() {
    status "Starting WildFly server..."
    "${JBOSS_HOME}/bin/standalone.sh" --admin-only | indent &
}

# Suspends the execution until the WildFly server is running.
#
# Returns:
#   always 0
_wait_until_wildfly_running() {
    until _is_wildfly_running; do
        sleep 1
    done
    status "WildFly is running"
}

# Checks if the WildFly server is running or not.
#
# Warning: The function requires the JBOSS_CLI environment variable
#          to be set correctly.
#
# Returns:
#   0: The server is running
#   1: The server is not running
_is_wildfly_running() {
    "${JBOSS_CLI}" --connect --command=":read-attribute(name=server-state)" 2>/dev/null | grep -q "running"
}

# Shuts the WildFly server down if it is running.
#
# Warning: The function requires the JBOSS_CLI environment variable
#          to be set correctly.
#
# Returns:
#   always 0
_shutdown_wildfly_server() {
    if _is_wildfly_running; then
        status "Shutdown WildFly server"
        "${JBOSS_CLI}" --connect --command=":shutdown" | indent && echo
    fi
}

# Registers an ERR trap for shutting down the WildFly server on
# an error before exiting.
_shutdown_on_error() {
    debug "Registering ERR trap for shutting down WildFly server on error"
    trap '_shutdown_wildfly_server; exit 1' ERR
}

# Looks for a WildFly installation under the '.jboss' directory and
# sets the corresponding environment variables. If the JBOSS_HOME
# environment variable is unset or there is no valid WildFly installation
# below this directory, the function produces an error.
#
# Params:
#   $1:  buildDir  The Heroku build directory
#
# Returns:
#   0: The WildFly installation could be located successfully
#   1: The WildFly installation could not be found or JBOSS_HOME is unset.
_load_wildfly_environment_variables() {
    local buildDir="$1"

    if [ -d "${buildDir}/.jboss" ] && [ -z "${JBOSS_HOME}" ]; then
        # Expand the WildFly directory with a glob to get the directory name
        # and version
        local wildflyDir=("${buildDir}"/.jboss/wildfly-*)
        if [ "${#wildflyDir[@]}" -eq 1 ] && [ -d "${wildflyDir[0]}" ]; then
            debug "WildFly installation found at '${wildflyDir[0]}'"

            export JBOSS_HOME="${JBOSS_HOME:-"${wildflyDir[0]}"}" && debug_var "JBOSS_HOME"
            export JBOSS_CLI="${JBOSS_CLI:-"${JBOSS_HOME}/bin/jboss-cli.sh"}" && debug_var "JBOSS_CLI"
            export WILDFLY_VERSION="${WILDFLY_VERSION:-"${JBOSS_HOME#*wildfly-}"}" && debug_var "WILDFLY_VERSION"
        fi
    fi

    # Verify the existence of a WildFly installation under JBOSS_HOME
    if [ -z "${JBOSS_HOME}" ] || \
       [ ! -d "${JBOSS_HOME}" ] || \
       [ ! -f "${JBOSS_HOME}/bin/standalone.sh" ]; then
        error_jboss_home_not_set
        return 1
    fi
}