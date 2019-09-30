# Heroku WildFly PostgreSQL Buildpack

[![Heroku Elements](https://img.shields.io/badge/Heroku_Elements-published-6762A6)][heroku-elements]
[![Buildpack Registry](https://img.shields.io/badge/Buildpack_Registry-mterhart/wildfly--postgresql-6762A6)][buildpack-registry]
[![Latest GitHub Release](https://img.shields.io/github/v/tag/mortenterhart/heroku-buildpack-wildfly-postgresql?color=blue&label=Latest%20Release&logo=github)][github-releases]

[heroku-elements]: https://elements.heroku.com/buildpacks/mortenterhart/heroku-buildpack-wildfly-postgresql "Buildpack on Heroku Elements"
[buildpack-registry]: https://devcenter.heroku.com/articles/buildpack-registry "Buildpack Registry"
[github-releases]: https://github.com/mortenterhart/heroku-buildpack-wildfly-postgresql/releases "GitHub Releases"

This is a [Heroku Buildpack](https://devcenter.heroku.com/articles/buildpacks) for
adding a PostgreSQL Driver and Datasource to an existing [Wildfly AS](http://wildfly.org).

This buildpack is intended to be used in conjunction with the [Wildfly Buildpack][wildfly-buildpack].

## Standalone Usage

### Using with the Java and Wildfly Buildpacks

You can use the standard [Heroku Java buildpack][java-buildpack] for creating a WAR file,
the [Wildfly buildpack][wildfly-buildpack] for downloading and installing a Wildfly
instance and this buildpack to add a driver and a datasource for the official
[Heroku PostgreSQL addon][heroku-postgresql-addon]. The addon is automatically
provisioned with the free `hobby-dev` plan for your application by this buildpack.

```bash
heroku buildpacks:clear
heroku buildpacks:add heroku/java
heroku buildpacks:add mterhart/wildfly
heroku buildpacks:add mterhart/wildfly-postgresql
```

This buildpack depends on the [Wildfly buildpack][wildfly-buildpack] that installs
the Wildfly server in the requested version to the correct location. So make sure
to add the buildpacks in the correct order.

## Usage from a Buildpack

```bash
WILDFLY_POSTGRESQL_BUILDPACK_URL="https://buildpack-registry.s3.amazonaws.com/buildpacks/mterhart/wildfly-postgresql.tgz"
mkdir -p /tmp/wildfly-postgresql-buildpack
curl --retry 3 --silent --location "${WILDFLY_POSTGRESQL_BUILDPACK_URL}" | tar xzm -C /tmp/wildfly-postgresql-buildpack --strip-components=1

source /tmp/wildfly-postgresql-buildpack/lib/postgresql_driver.sh
source /tmp/wildfly-postgresql-buildpack/lib/postgresql_datasource.sh
```

### Specifying a specific Revision of the Buildpack

You can use another revision of this buildpack for your own one. Simply change the
buildpack URL and append a version specifier to the filename, for example `v15`.
Then change the line in your script to the following:

```bash
WILDFLY_BUILDPACK_URL="https://buildpack-registry.s3.amazonaws.com/buildpacks/mterhart/wildfly-postgresql-v15.tgz"
```

## Configuration

### Config Vars

| **Name** | **Default Value** | **Description** |
|:--------:|:-----------------:|:----------------|
| `DATASOURCE_NAME`  | `appDS` | The name of the PostgreSQL datasource |
| `DATASOURCE_JNDI_NAME` | `java:jboss/datasources/appDS` | The JNDI name of the persistence unit defined in `persistence.xml`. Overrides the value automatically read from `persistence.xml`. |
| `POSTGRESQL_DRIVER_NAME` | `postgresql` | |
| `ONLY_INSTALL_DRIVER` | `false` | When set to `true` this buildpack will only install the driver and not create the datasource for WildFly. |
| `WAR_PERSISTENCE_XML_PATH` | unset |  |
| `JBOSS_HOME` | automatically set | The path to the WildFly home directory |
| `HIBERNATE_DIALECT_AUTO_UPDATE` | `true` | When set to `true` the auto update for the Hibernate dialect in the `persistence.xml` is disabled. |
| `HIBERNATE_DIALECT` | `org.hibernate.dialect.PostgreSQL95Dialect` | The Hibernate dialect that is automatically updated |

### Configuring the Wildfly version

Create a `system.properties` file in the root directory of your project and set
the `wildfly.version` property as follows:

```properties
wildfly.version=16.0.0.Final
```

This is necessary because the buildpack needs to know the location of the Wildfly
installation directory.

### PostgreSQL Driver

The buildpack downloads the PostgreSQL JDBC Driver Version `42.2.1` and adds it
to the Wildfly server as a module first. The driver is then installed at the
Wildfly server.

### Configuring the PostgreSQL Datasource

By default, the buildpack looks for the file `src/main/resources/META-INF/persistence.xml`
to determine the JNDI name and datasource name used by the project. A new datasource
matching these names is then added to the Wildfly server.

An example for a valid `persistence.xml` is:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<persistence xmlns="http://xmlns.jcp.org/xml/ns/persistence"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://xmlns.jcp.org/xml/ns/persistence
             http://xmlns.jcp.org/xml/ns/persistence/persistence_2_1.xsd"
             version="2.1">

    <persistence-unit name="app" transaction-type="JTA">
        <provider>org.hibernate.jpa.HibernatePersistenceProvider</provider>
        <jta-data-source>java:jboss/datasources/appDS</jta-data-source>
        <properties>
            <property name="hibernate.dialect" value="org.hibernate.dialect.PostgreSQL95Dialect"/>
            <property name="hibernate.transaction.manager_lookup_class"
                      value="org.hibernate.transaction.JBossTransactionManagerLookup"/>
            <property name="hibernate.show_sql" value="false"/>
            <property name="hibernate.hbm2ddl.auto" value="update"/>
        </properties>
    </persistence-unit>
</persistence>
```

The value inside the `<jta-data-source>` tag is used as JNDI name and the name of
the persistence unit including a trailing `DS` is used as name for the new datasource.

### Auto-updating the Hibernate Dialect

When using Hibernate as a JPA provider like in the example above the buildpack
changes the Hibernate Dialect automatically to PostgreSQL. This is done by
replacing the given value in the `persistence.xml`.

[java-buildpack]: https://github.com/heroku/heroku-buildpack-java "Heroku Java Buildpack"
[wildfly-buildpack]: https://github.com/mortenterhart/heroku-buildpack-wildfly "WildFly buildpack"
[heroku-postgresql-addon]: https://elements.heroku.com/addons/heroku-postgresql "Heroku PostgreSQL Addon"
