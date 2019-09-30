#!/usr/bin/env bash

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

        sed -Ei "s#org\.hibernate\.dialect\.[A-Za-z0-9]+Dialect#${dialect}#" "${persistenceFile}"
    fi
}

validate_hibernate_dialect() {
    local dialect="$1"

    local hibernateDocsBaseUrl="https://docs.jboss.org/hibernate/orm/current/javadocs"
    local referenceUrl="${hibernateDocsBaseUrl}/org/hibernate/dialect/package-summary.html"

    if ! [[ "${dialect}" =~ ^org\.hibernate\.dialect ]]; then
        error_invalid_hibernate_dialect_namespace "${dialect}" "${referenceUrl}"
        return 1
    fi

    if ! [[ "${dialect}" =~ PostgreSQL[8-9]?[0-5]?Dialect$ ]]; then
        error_not_a_postgresql_dialect "${dialect}" "${referenceUrl}"
        return 1
    fi

    local docsUrl="${hibernateDocsBaseUrl}/${dialect//.//}.html"
    if [ "$(_get_url_status "${docsUrl}")" != "200" ]; then
        error_unsupported_hibernate_dialect "${dialect}" "${referenceUrl}"
        return 1
    fi
}