#!/bin/bash
set -e

# Require PGHOST, PGUSER, PGPASSWORD be set by the caller
set -u
: "$PGHOST"
: "$PGUSER"
: "$PGPASSWORD"

# Azure user connection string will be of the form:
# administatorLogin@serverName
# but need administratorLogin (e.g., postgres)
SUPERUSER=${PGUSER%@*}
TEMPLATE_DB=template1

export PGOPTIONS='--client-min-messages=warning'
PSQL_OPTS='-v ON_ERROR_STOP=1 -X -q'

create_role () {
  role=$1
  psql $PSQL_OPTS -d $TEMPLATE_DB -f - <<EOF
    DO \$\$
    BEGIN
      CREATE ROLE $role;
      EXCEPTION WHEN DUPLICATE_OBJECT THEN
      RAISE NOTICE 'role "$role" already exists';
    END
    \$\$;
EOF
}

baseline_template () {
  psql $PSQL_OPTS -d $TEMPLATE_DB -f - <<EOF 
    REVOKE ALL ON DATABASE $TEMPLATE_DB FROM public;
    REVOKE ALL ON SCHEMA public FROM public;
    GRANT ALL ON SCHEMA public TO $SUPERUSER;
    CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;
EOF
}

alter_base_role () {
  base=$1
  psql $PSQL_OPTS -d $TEMPLATE_DB -f - <<EOF 
    ALTER ROLE $base RESET ALL;
    ALTER ROLE $base NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOLOGIN;
EOF
}

alter_owner_role () {
  base=$1
  owner=$2
  psql $PSQL_OPTS -d $TEMPLATE_DB -f - <<EOF 
    ALTER ROLE $owner RESET ALL;
    -- TODO Managed identity configuration should be established here
    ALTER ROLE $owner NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    GRANT $base TO $owner;
EOF
}

create_db () {
  db=$1
  owner=$2
  psql $PSQL_OPTS -d $TEMPLATE_DB -f - <<EOF 
    -- "superuser" account under Azure is not so super; must be a member of the
    -- owner role before being able to create a database with it as owner
    GRANT $owner to $SUPERUSER;
    SELECT 'CREATE DATABASE $db OWNER $owner TEMPLATE $TEMPLATE_DB'
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db')\gexec
    REVOKE $owner from $SUPERUSER;
    REVOKE ALL ON DATABASE $db FROM public;
EOF
}

alter_db_schema () {
  db=$1
  owner=$2
  psql $PSQL_OPTS -d $db -f - <<EOF 
    GRANT ALL ON SCHEMA public TO $owner WITH GRANT OPTION;
EOF
}

# Following guidance from:
# https://wiki.postgresql.org/wiki/Shared_Database_Hosting

echo "Baseline $TEMPLATE_DB before creating new databases from it"
baseline_template

# Use the state abbreviation as the name of the db,
# the base db role, and the prefix for the db owner role.
while IFS=, read -r abbr name ; do
  echo "Creating roles and database for $name ($abbr)"

  base=`echo "$abbr" | tr '[:upper:]' '[:lower:]'`
  owner=${base}owner

  create_role $base
  alter_base_role $base

  create_role $owner
  alter_owner_role $base $owner
  
  create_db $base $owner
  alter_db_schema $base $owner
done < states.csv
