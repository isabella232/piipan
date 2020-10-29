#!/bin/sh

RESOURCE_GROUP=piipan-resources
LOCATION=westus
OBJECT_ID=`az ad signed-in-user show --query objectId --output tsv`

echo "Creating $RESOURCE_GROUP group"
az group create --name $RESOURCE_GROUP -l $LOCATION

# Create a key vault which will store credentials for use in other templates
az deployment group create \
	--name secret-keeper \
	--resource-group $RESOURCE_GROUP \
	--template-file ./arm-templates/key-vault.json \
	--parameters \
		location=$LOCATION \
		objectId=$OBJECT_ID

# For each participating state, create a separate storage account.
# Each account has a blob storage container named `upload`.
while IFS=, read -r abbr name ; do 
    echo "Creating storage for $name ($abbr)"
    az deployment group create \
		--name "${abbr}-blob-storage" \
		--resource-group $RESOURCE_GROUP \
		--template-file ./arm-templates/blob-storage.json \
		--parameters stateAbbreviation=$abbr
done < states.csv

