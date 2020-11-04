#!/bin/bash
set -e

RESOURCE_GROUP=piipan-resources
LOCATION=westus
PROJECT_TAG=piipan
RESOURCE_TAGS="{ \"Project\": \"${PROJECT_TAG}\" }"

# Identity object ID for the Azure environment owner
OBJECT_ID=`az ad signed-in-user show --query objectId --output tsv`

# Name of Key Vault
VAULT_NAME=secret-keeper

# Name of secret used to store the PostgreSQL server admin password
PG_SECRET_NAME=particpants-records-admin

# Name of administrator login for PostgreSQL server
PG_SUPERUSER=postgres

# Name of PostgreSQL server
PG_SERVER_NAME=participant-records

# Name of App Service Plan
APP_SERVICE_PLAN=piipan-app-plan

# Base name of dashboard app
DASHBOARD_APP_NAME=piipan-dashboard

# Create a very long, (mostly) random password. Ensures all Azure character
# class requirements are met by tacking on a non-random, tailored suffix.
random_password () {
  head /dev/urandom | LC_ALL=C tr -dc "A-Za-z0-9" | head -c 64 ; echo -n 'aA1!'
}

echo "Creating $RESOURCE_GROUP group"
az group create --name $RESOURCE_GROUP -l $LOCATION --tags Project=$PROJECT_TAG

# Create a key vault which will store credentials for use in other templates
az deployment group create \
  --name $VAULT_NAME \
  --resource-group $RESOURCE_GROUP \
  --template-file ./arm-templates/key-vault.json \
  --parameters \
    location=$LOCATION \
    objectId=$OBJECT_ID \
    resourceTags="$RESOURCE_TAGS"

# For each participating state, create a separate storage account.
# Each account has a blob storage container named `upload`.
while IFS=, read -r abbr name ; do 
    echo "Creating storage for $name ($abbr)"
    az deployment group create \
    --name "${abbr}-blob-storage" \
    --resource-group $RESOURCE_GROUP \
    --template-file ./arm-templates/blob-storage.json \
    --parameters \
      stateAbbreviation=$abbr \
      resourceTags="$RESOURCE_TAGS"
done < states.csv

# Avoid echoing passwords in a manner that may show up in process listing,
# or storing it in a temp file that may be read, or appearing in a CI/CD log.
#
# By default, Azure CLI will print the password set in Key Vault; instead
# just extract and print the secret id from the JSON response.
export PG_SECRET=`random_password`
printenv PG_SECRET | tr -d '\n' | az keyvault secret set \
  --vault-name $VAULT_NAME \
  --name $PG_SECRET_NAME \
  --file /dev/stdin \
  --query id

echo "Creating PostgreSQL server"
az deployment group create \
  --name participant-records \
  --resource-group $RESOURCE_GROUP \
  --template-file ./arm-templates/participant-records.json \
  --parameters \
    administratorLogin=$PG_SUPERUSER \
    serverName=$PG_SERVER_NAME \
    secretName=$PG_SECRET_NAME \
    vaultName=$VAULT_NAME \
    resourceTags="$RESOURCE_TAGS"

export PGPASSWORD=$PG_SECRET
export PGUSER=${PG_SUPERUSER}@${PG_SERVER_NAME}
export PGHOST=`az resource show \
  --resource-group $RESOURCE_GROUP \
  --name $PG_SERVER_NAME \
  --resource-type "Microsoft.DbForPostgreSQL/servers" \
  --query properties.fullyQualifiedDomainName -o tsv`

./create-databases.bash

# Create App Service resources for dashboard app
echo "Creating App Service resources for dashboard app"
az deployment group create \
	--name $DASHBOARD_APP_NAME \
	--resource-group $RESOURCE_GROUP \
	--template-file ./arm-templates/dashboard-app.json \
	--parameters \
    location=$LOCATION \
    resourceTags="$RESOURCE_TAGS" \
    appName=$DASHBOARD_APP_NAME \
		servicePlan=$APP_SERVICE_PLAN
