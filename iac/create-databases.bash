#!/bin/bash
set -e

# Require PGHOST, PGUSER, PGPASSWORD be set by the caller;
# PGUSER and PGPASSWORD should correspond to the out-of-the-box,
# non-AD "superuser" administrtor login
set -u
: "$PGHOST"
: "$PGUSER"
: "$PGPASSWORD"

# Azure user connection string will be of the form:
# administatorLogin@serverName
# but need those values separately
SUPERUSER=${PGUSER%@*}
PG_SERVER_NAME=${PGUSER#*@}
TEMPLATE_DB=template1
# Nest all tables under a schema for easier control,
# as public is owned by azure_superuser
APP_SCHEMA=piipan

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

config_db () {
  db=$1
  psql $PSQL_OPTS -d $db -f - <<EOF
    REVOKE ALL ON DATABASE $db FROM public;
    REVOKE ALL ON SCHEMA public FROM public;
    CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;
EOF
}

config_role () {
  role=$1
  psql $PSQL_OPTS -d $TEMPLATE_DB -f - <<EOF
    ALTER ROLE $role PASSWORD NULL;
    ALTER ROLE $role NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOLOGIN;
    ALTER ROLE $role SET search_path = piipan,public;
EOF
}

create_db () {
  db=$1
  psql $PSQL_OPTS -d $TEMPLATE_DB -f - <<EOF
    SELECT 'CREATE DATABASE $db TEMPLATE $TEMPLATE_DB'
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db')\gexec
EOF
  psql $PSQL_OPTS -d $db -f - <<EOF
    CREATE SCHEMA IF NOT EXISTS $APP_SCHEMA;
EOF
}

set_db_owner () {
  db=$1
  owner=$2
  psql $PSQL_OPTS -d $db -f - <<EOF
    -- "superuser" account under Azure is not so super; must be a member of the
    -- owner role before being able to create a database with it as owner
    GRANT $owner to $SUPERUSER;
    ALTER DATABASE $db OWNER TO $owner;
    ALTER SCHEMA $APP_SCHEMA OWNER TO $owner;
    REVOKE $owner from $SUPERUSER;
EOF
}

create_managed_role () {
  db=$1
  role=$2
  client_id=$3
  # XXX If the role already exists, we assume it is already associated with the
  # client id specified.
  # This isn't quite consistent with the Azure Resource Manager incremental mode
  # philosophy we've attempted to emulate, where all properties are reapplied.
  # We could drop the role and re-create it, but would require revoking and then
  # restoring all privileges. We might be able to calculate the MD5 hash and compare
  # to value in pg_authid and then at least error and exit if they didn't match.
  psql $PSQL_OPTS -d $TEMPLATE_DB -f - <<EOF
    SET aad_validate_oids_in_tenant = off;
    DO \$\$
    BEGIN
      CREATE ROLE $role LOGIN PASSWORD '$client_id' IN ROLE azure_ad_user;
      EXCEPTION WHEN DUPLICATE_OBJECT THEN
      RAISE NOTICE 'role "$role" already exists';
    END
    \$\$;
EOF
}

config_managed_role () {
  db=$1
  role=$2
  psql $PSQL_OPTS -d $db -f - <<EOF
    GRANT CONNECT,TEMPORARY ON DATABASE $db TO $role;
    GRANT $db to $role;
    GRANT USAGE ON SCHEMA $APP_SCHEMA to $role;
    ALTER ROLE $role NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
    ALTER ROLE $role SET search_path = $APP_SCHEMA,public;
EOF
}

# Trading off isolation and cost, use a single PostgreSQL cluster to host
# separate databases for each participating state.
#
# This is re-runnable, preserving any existing data in the cluster, in the
# spirit of an ARM template. It expects that the PostgreSQL cluster and
# managed identities have already been established.
#
# For example, if Echo Alpha (EA) state is in states.csv, we will get:
# - a database `ea` owned by `ea` role
# - a schema `piipan` in that db owned by `ea` role
# - `eaadmin` role corresponding to the AD managed identity of the same name
# - `eaadmin` made a member of `ea` role; sessions must `SET ROLE to ea`
#    to execute any DDL to create tables, etc.
#
# There are several constraints using Azure Database for PostgreSQL and
# managed identities that must be accommodated:
#   - a "superuser" account must be in a role to create resources as that role
#   - Managed identity roles can only be created by the PostgreSQL server
#     Active Directory admin, not the out-of-the-box, non-AD "superuser" login
#   - Active Directory roles (e.g., managed identities or the AD admin
#     user/group for the cluster) cannot be added to non-AD roles
#   - Managed identitiy roles can only be established through CREATE, not via 
#     GRANT on an existing role; this is likely due to the identity client id
#     being specified via the password parameter, which is stored as a one-way
#     hash in pg_authid
#
# See related guidance:
# https://wiki.postgresql.org/wiki/Shared_Database_Hosting
# https://info.enterprisedb.com/rs/069-ALB-339/images/Multitenancy%20Approaches%20Whitepaper.pdf
main () {
  RESOURCE_GROUP=$1

  echo "Baseline $TEMPLATE_DB before creating new databases from it"
  config_db $TEMPLATE_DB

  # Use the state abbreviation as the name of the db and its owner
  while IFS=, read -r abbr name ; do
    echo "Creating owner role and database for $name ($abbr)"

    db=`echo "$abbr" | tr '[:upper:]' '[:lower:]'`
    owner=$db

    create_role $owner
    config_role $owner

    create_db $db
    set_db_owner $db $owner
    config_db $db
  done < states.csv

  # Assumes there's only the single admin group that was set elsewhere
  PG_AAD_ADMIN=`az postgres server ad-admin list \
    --server-name $PG_SERVER_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "[0].login" -o tsv`

  # Initial environment variables are for the non-AD "superuser"
  SAVED_PGPASSWORD=$PGPASSWORD
  SAVED_PGUSER=$PGUSER

  # Authenticate under the AD "superuser" group, in order to create managed
  # identities. Assumes the current user is a member of PG_AAD_ADMIN.
  export PGPASSWORD=`az account get-access-token --resource-type oss-rdbms \
     --query accessToken --output tsv`
  export PGUSER=${PG_AAD_ADMIN}@$PG_SERVER_NAME

  while IFS=, read -r abbr name ; do
    echo "Creating managed identity roles for $name ($abbr)"

    db=`echo "$abbr" | tr '[:upper:]' '[:lower:]'`

    # As in create-resources.bash, managed identities use the
    # state abbreviation as its prefix, and `admin` as its suffix
    identity=${db}admin
    client_id=`az identity show \
      --resource-group $RESOURCE_GROUP \
      --name $identity \
      --query clientId --output tsv`

    # Database role has the same name as its corresponding AD managed identity
    role=$identity
    create_managed_role $db $role $client_id
    config_managed_role $db $role
  done < states.csv
}

main "$@"
