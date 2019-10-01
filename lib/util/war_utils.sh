#!/usr/bin/env bash

# Locates the WAR file from the WildFly deployments that contains
# a persistence unit under a certain path. The persistence unit
# is defined in the persistence.xml file and contains the persistence
# provider (Hibernate in most cases), the datasource JNDI name and
# custom properties such as the Hibernate dialect. The first WAR
# file matching the path is returned, i.e. the first persistence
# unit found is taken as the result.
#
# Params:
#   $1:  persistenceFilePath  the path to the persistence file
#                             relative to the root of the WAR file
#
# Returns:
#   stdout: the path to the WAR file containing the persistence
#           unit
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

# Examines whether a given WAR file contains a provided file path.
# The file path has to be relative to the root directory inside the
# WAR file in order to check for existence correctly.
#
# Params:
#   $1:  warFile  the WAR file
#   $2:  file     the file to check for existence in the WAR file
#
# Returns:
#   0: The WAR file contains the provided file.
#   1: The file does not exist in the WAR file.
_war_file_contains_file() {
    local warFile="$1"
    local file="$2"

    if [ ! -f "${warFile}" ]; then
        return 1
    fi

    unzip -q -l "${warFile}" "${file}" >/dev/null
}

# Updates a single file in the WAR file. The function switches to
# a supplied root directory under which the directory structure of
# the WAR file needs to exist in order to update it. The file needs
# to exist here under the corresponding path in the WAR file relative
# to the root directory. This relative path needs to be supplied as
# file argument to this function.
#
# Params:
#   $1:  warFile       the path to the WAR file
#   $2:  rootDir       the root directory with the directory
#                      structure of the WAR file
#   $3:  relativeFile  the file to update relative to the root
#                      directory
#
# Returns:
#   0: The file was updated in the WAR file successfully.
#   1: An error occurred
#
# Example:
#   /tmp/root / WEB-INF/classes/META-INF/persistence.xml
#   |-------|   |--------------------------------------|
#    rootDir                  relativeFile
#
#   update_file_in_war "deployment.war" "/tmp/root" "WEB-INF/classes/META-INF/persistence.xml"
#
#   Updates the file "WEB-INF/classes/META-INF/persistence.xml" in
#   the WAR file "deployment.war".
#
#   The root path is necessary because the 'zip' command requires
#   the same directory structure as in the WAR file to exist under
#   the current working directory.
#
update_file_in_war() {
    local warFile="$1"
    local rootDir="$2"
    local relativeFile="$3"

    if [ ! -d "${rootDir}" ]; then
        error_return "Root path needs to be a directory: ${rootDir}"
        return 1
    fi

    if [ ! -f "${rootDir}/${relativeFile}" ]; then
        error_return "Relative file does not exist under root path: ${relativeFile}"
        return 1
    fi

    # Transform the path to the WAR file to an absolute path
    # so that it is found in the directory to that is switched
    # to before the 'zip' command is executed.
    if _is_relative_path "${warFile}"; then
        warFile="$(_resolve_absolute_path "${warFile}")"
    fi

    status "Patching '${warFile##*/}' with updated persistence.xml"
    debug_command "zip -q --update \"${warFile}\" \"${relativeFile}\""

    (cd "${rootDir}" && zip -q --update "${warFile}" "${relativeFile}")
}