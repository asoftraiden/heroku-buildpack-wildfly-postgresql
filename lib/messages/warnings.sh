#!/usr/bin/env bash

# Writes a formatted warning message provided on stdin to the standard
# output and resumes the build execution. If no input is provided on
# stdin the function produces an error and exits.
#
# Input:
#   stdin:  the warning message
#
# Returns:
#   stdout: the formatted warning message
#   0: The warning message was written to stdout
#   1: The warning message was not supplied on stdin
write_warning() {
    if [ -t 0 ]; then
        error "Warning message on stdin expected. Use a heredoc to write it."
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
    local warningMessage
    read -r -d '' warningMessage || true

    warning "${warningMessage}"
}

# Writes a warning message about the 'errexit' Shell option being not
# set.
#
# Returns:
#   always 0
warning_errexit_not_set() {
    write_warning << WARNING
'errexit' Shell option not set

You should use 'set -e' in your script as this buildpack relies
on error handling by exit status. Without it the build continues
on errors and may cause undesired results.
WARNING
}

# Writes a warning message about the 'errtrace' Shell option being not
# set.
#
# Returns:
#   always 0
warning_errtrace_not_set() {
    write_warning <<WARNING
'errtrace' Shell option not set

When using 'set -e' (errexit) you should also use 'set -E'
(errtrace) to ensure ERR traps are working properly. The
'errtrace' option ensures that ERR traps are also in effect
in Shell functions.

ERR traps are usually used for cleanup or failure handling
after an error encountered. This buildpack uses an ERR trap
to shutdown the WildFly server after an error.
WARNING
}

# Writes a warning message about a missing persistence unit.
#
# Params:
#   $1:  warPersistencePath  the path inside the WAR file to the
#                            persistence.xml file
#
# Returns:
#   always 0
warning_no_persistence_unit_found() {
    local warPersistencePath="$1"

    write_warning <<WARNING
No Persistence Unit found in any WAR file. Database connections will not be possible.

The buildpack looks for a persistence.xml definition at the path
'${warPersistencePath}' in all deployed WAR files.
The path can be altered by setting the WAR_PERSISTENCE_XML_PATH
config var which overrides the default value:

  heroku config:set WAR_PERSISTENCE_XML_PATH=path/in/war

Ensure that your path is relative to the root of the WAR archive.
WARNING
}

# Writes a warning message about a boolean config var having an
# invalid value other than 'true' or 'false'.
#
# Params:
#   $1:  configVar     the name of the config var
#   $2:  defaultValue  the default value of the config var
#
# Returns:
#   always 0
warning_config_var_invalid_boolean_value() {
    local configVar="$1"
    local defaultValue="$2"

    local configValue="${!configVar}"

    write_warning <<WARNING
Invalid value for ${configVar} config var: '${configValue}'
Valid values include 'true' and 'false'. Using default value '${defaultValue}'.
WARNING
}
