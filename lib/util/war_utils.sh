#!/usr/bin/env bash

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
    debug_command "zip -q --update \"${warFile}\" \"${relativeFile}\""

    (cd "${rootPath}" && zip -q --update "${warFile}" "${relativeFile}")
}