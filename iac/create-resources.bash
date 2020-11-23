#!/bin/bash
set -e
set -u

RESOURCE_GROUP=piipan-resources
LOCATION=westus
PROJECT_TAG=piipan
RESOURCE_TAGS="{ \"Project\": \"${PROJECT_TAG}\" }"

# Identity object ID for the Azure environment account
CURRENT_USER_OBJID=`az ad signed-in-user show --query objectId --output tsv`

# Name of Key Vault
VAULT_NAME=secret-keeper

# Name of secret used to store the PostgreSQL server admin password
PG_SECRET_NAME=particpants-records-admin

# Name of administrator login for PostgreSQL server
PG_SUPERUSER=postgres

# Name of Azure Active Directory admin for PostgreSQL server
PG_AAD_ADMIN=piipan-admins

# Name of PostgreSQL server
PG_SERVER_NAME=participant-records

# Name of App Service Plan
APP_SERVICE_PLAN=piipan-app-plan

# Base name of dashboard app
DASHBOARD_APP_NAME=piipan-dashboard

# Display name of service principal account responsible for CI/CD tasks
SP_NAME_CICD=piipan-cicd

# Create a service principal with the provided name and store its client_id
# and client_secret values in the key vault.
#
# Only create the SP if one with the provided name does not already exist.
# Running the create command on an existing service principal will "patch"
# the account and reset the password.
create_and_store_sp () {
  name=$1
  if [ -z `az ad sp list --display-name $name --query "[].appId" --output tsv` ]
    then
      # Service principal does not exist. Create and store secret in vault.
      scope=`az group show -n $RESOURCE_GROUP --query id --output tsv`
      secret=`az ad sp create-for-rbac \
        --name $name \
        --scope $scope \
        --query password \
        --output tsv`
      id=`az ad sp show --id http://$name --query appId --output tsv`

      az keyvault secret set \
        --vault-name $VAULT_NAME \
        --name $id \
        --value $secret \
        --output none

      az keyvault secret set-attributes \
        --vault-name $VAULT_NAME \
        --name $id \
        --content-type "$name service principal credentials"

      echo "Service principal $name created."
    else
      echo "Service principal $name already exists."
  fi
}

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
    objectId=$CURRENT_USER_OBJID \
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

# The AD admin can't be specified in the PostgreSQL ARM template,
# unlike in Azure SQL
az ad group create --display-name $PG_AAD_ADMIN --mail-nickname $PG_AAD_ADMIN
PG_AAD_ADMIN_OBJID=`az ad group show --group $PG_AAD_ADMIN --query objectId --output tsv`
az postgres server ad-admin create \
  --resource-group $RESOURCE_GROUP \
  --server $PG_SERVER_NAME \
  --display-name $PG_AAD_ADMIN \
  --object-id $PG_AAD_ADMIN_OBJID

# Create managed identities to admin each state's database
while IFS=, read -r abbr name ; do
    echo "Creating managed identity for $name ($abbr)"
    abbr=`echo "$abbr" | tr '[:upper:]' '[:lower:]'`
    identity=${abbr}admin
    az identity create -g $RESOURCE_GROUP -n $identity
done < states.csv

# Temporarily add current user as a PostgreSQL AD admin to allow provisioning of
# managed identity roles; assumes it is not already a member.
az ad group member add --group $PG_AAD_ADMIN --member-id $CURRENT_USER_OBJID

export PGPASSWORD=$PG_SECRET
export PGUSER=${PG_SUPERUSER}@${PG_SERVER_NAME}
export PGHOST=`az resource show \
  --resource-group $RESOURCE_GROUP \
  --name $PG_SERVER_NAME \
  --resource-type "Microsoft.DbForPostgreSQL/servers" \
  --query properties.fullyQualifiedDomainName -o tsv`

./create-databases.bash $RESOURCE_GROUP

# Remove current user as a PostgreSQL AD admin
az ad group member remove --group $PG_AAD_ADMIN --member-id $CURRENT_USER_OBJID

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

# Create a service principal for use by CircleCI.
create_and_store_sp $SP_NAME_CICD