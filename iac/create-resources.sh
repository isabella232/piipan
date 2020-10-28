#!/bin/sh

RESOURCE_GROUP=piipan-resources
REGION=westus

echo "Creating $RESOURCE_GROUP group"
az group create --name $RESOURCE_GROUP -l $REGION

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
