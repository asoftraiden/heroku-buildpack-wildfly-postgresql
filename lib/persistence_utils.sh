#!/usr/bin/env bash
#
# shellcheck disable=SC2155

update_hibernate_dialect() {
    local warFile="$1"
    local persistenceFile="$2"
    local dialect="$3"

    # Verify that the given war file exists and that it
    # contains the persistence.xml
    if [ -f "${warFile}" ] && unzip -l -q "${warFile}" "${persistenceFile}" >/dev/null; then
        # Extract the persistence.xml to a temporary directory
        local warBasename="${warFile##*/}"
        local extractionDirectory="$(mktemp -d "/tmp/${warBasename%.war}.XXXXXX")"
        unzip -q -d "${extractionDirectory}" "${warFile}" "${persistenceFile}"

        # Replace Hibernate dialect to passed one
        sed -Ei "s#org\.hibernate\.dialect\.[A-Za-z0-9]+Dialect#${dialect}#" "${extractionDirectory}/${persistenceFile}"

        # Copy the WAR file to the extraction directory
        cp -f "${warFile}" "${extractionDirectory}"

        # Patch the copied WAR file inside the temporary directory
        # with the updated persistence.xml
        (cd "${extractionDirectory}" && zip --update "${warBasename}" "${persistenceFile}" >/dev/null)

        # Move the WAR file back to its original path
        # overwriting the original file
        mv -f "${extractionDirectory}/${warBasename}" "${warFile}"

        # Delete the temporary extraction directory
        rm -rf "${extractionDirectory}"
    fi
}