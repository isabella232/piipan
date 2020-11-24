# CI/CD Pipeline

## CircleCI

We use CircleCI to automate the build and deployment of our subsystems.

### Environment variables

CircleCI is configured with several environment variables that provide information and credentials necessary to automate deployment to Azure.

| Environment variable | Value |
|---|---|---|
| `AZURE_RESOURCE_GROUP` | Name of resource group where services will be deployed (e.g., "piipan-resources") |
| `APP_NAME` | Name of [dashboard app](dashboard.md) |
| `AZURE_SP` | Service principal `appId` (aka `clientId`) |
| `AZURE_SP_PASSWORD` | Service principal `password` (aka `clientSecret`)|
| `AZURE_SP_TENANT` | Service principal `appOwnerTenantId` |

The three environment variables beginning with `AZURE_SP` provide CircleCI with credentials for an Azure service principal. The credentials are used to log in to the Azure CLI via a user ID and password that are provided to the [circleci/azure-cli orb](https://circleci.com/developer/orbs/orb/circleci/azure-cli).

A service principal named `piipan-cicd` (note, this is the *display name* and not the *`appId`*) is created as part of the IaC process and intended to be used by CircleCI. The credentials are stored as a secret in an Azure key vault and can be accessed either through the Azure CLI or web portal.

**Web portal**:  Go to Portal > Key vaults > secret-keeper > secrets. There will be a secret with a "Type" field set to "piipan-cicd service principal credentials". The name of the secret, a long string of letters and numbers, is the service principal `appId` (or `clientId`). The secret value is the service principal `password` (or `clientSecret`). The remaining value, `AZURE_SP_TENANT`, can be found in the "Tenant ID" field on Portal > Tenant properties page.

**Azure CLI**: First find the `appId` and `tenantId`:

```
    az ad sp show --id http://piipan-cicd --query '{appId:appId,tenantId:appOwnerTenantId}'
```

Then lookup the secret:

```
    az keyvault secret show --name <appId> --vault-name secret-keeper
```

*Note: Because of the way our IaC templates are structured, only the user who runs the IaC script is given access to the `secret-keeper` key vault. However, any admin can grant themselves access either by running the IaC script themselves, using the [CLI](https://docs.microsoft.com/en-us/cli/azure/keyvault?view=azure-cli-latest#az_keyvault_set_policy), or using the portal interface (Portal > Key vaults > secret-keeper > Access policies > Add Access Policy).*