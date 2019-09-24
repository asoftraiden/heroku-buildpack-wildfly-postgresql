#!/usr/bin/env bash

update_hibernate_dialect() {
    local persistenceFile="$1"
    local dialect="$2"

    if [ ! -f "${persistenceFile}" ]; then
        error_return "Passed persistence.xml file does not exist: ${persistenceFile}"
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