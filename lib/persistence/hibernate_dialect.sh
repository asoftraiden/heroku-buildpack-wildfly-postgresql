#!/usr/bin/env bash

# Checks if the supplied persistence file defines a Hibernate dialect
# and updates it to a new dialect in this case. The provided dialect
# is expected to be an available PostgreSQL dialect and is validated
# against the available Hibernate dialects. These can be issued at:
# https://docs.jboss.org/hibernate/orm/current/javadocs/org/hibernate/dialect/package-summary.html
#
# Params:
#   $1:  persistenceFile  the path to the persistence.xml file
#   $2:  dialect          the dialect to update to
#
# Returns:
#   0: The update was successful
#   1: Either the persistence file does not exist or the new dialect
#      is invalid
update_hibernate_dialect() {
    local persistenceFile="$1"
    local dialect="$2"

    if [ ! -f "${persistenceFile}" ]; then
        error_return "Passed persistence file does not exist: ${persistenceFile}"
        return 1
    fi

    if grep -Eq '<property [[:blank:]]*name="hibernate\.dialect"' "${persistenceFile}"; then
        status "Hibernate JPA detected: Changing Hibernate dialect to '${dialect}'"

        if ! validate_hibernate_dialect "${dialect}"; then
            return 1
        fi

        _replace_hibernate_dialect "${persistenceFile}" "${dialect}"
    fi
}

# Validates the configured Hibernate dialect by checking for correct
# dialect namespace, valid PostgreSQL dialect and existing dialect.
# An error is returned if any of those checks fails.
#
# Params:
#   $1:  dialect  the Hibernate dialect to validate
#
# Returns:
#   0: The configured Hibernate dialect is a valid PostgreSQL dialect.
#   1: The dialect is not a valid or existing PostgreSQL dialect.
validate_hibernate_dialect() {
    local dialect="$1"

    local hibernateDocsBaseUrl="https://docs.jboss.org/hibernate/orm/current/javadocs"
    local referenceUrl="${hibernateDocsBaseUrl}/org/hibernate/dialect/package-summary.html"

    # Check if the dialect has the correct namespace
    if ! [[ "${dialect}" =~ ^org\.hibernate\.dialect ]]; then
        error_invalid_hibernate_dialect_namespace "${dialect}" "${referenceUrl}"
        return 1
    fi

    # Check if the dialect is a PostgreSQL dialect
    if ! [[ "${dialect}" =~ PostgreSQL[8-9]?[0-5]?Dialect$ ]]; then
        error_not_a_postgresql_dialect "${dialect}" "${referenceUrl}"
        return 1
    fi

    # Check if the dialect exists. This is done by checking whether
    # the documentation webpage for the dialect exists. It does not
    # exist if the URL status is 404 Not Found.
    local docsUrl="${hibernateDocsBaseUrl}/${dialect//.//}.html"
    if [ "$(_get_url_status "${docsUrl}")" != "200" ]; then
        error_unsupported_hibernate_dialect "${dialect}" "${referenceUrl}"
        return 1
    fi
}

# Replaces the Hibernate dialect in the persistence file with the
# configured one in-place. This function takes care of the slight
# difference between the BSD and GNU 'sed' utilities when editing
# in-place.
#
# Params:
#   $1:  persistenceFile  the path to the persistence.xml file
#   $2:  dialect          the dialect to be replaced
#
# Returns:
#   0 unless the persistence file does not exist
_replace_hibernate_dialect() {
    local persistenceFile="$1"
    local dialect="$2"

    local sedCommand="s/org\.hibernate\.dialect\.[A-Za-z0-9]+Dialect/${dialect}/"

    case "$(uname)" in
        Darwin) sed -Ei '' "${sedCommand}" "${persistenceFile}" ;; # BSD 'sed' requires an empty argument to the -i (in-place) option to omit the backup
        *)      sed -Ei    "${sedCommand}" "${persistenceFile}" ;; # GNU 'sed' takes no argument to the -i option in order to omit the backup
    esac
}