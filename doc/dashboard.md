# Dashboard application

## Prerequisites
- [.NET Core SDK](https://dotnet.microsoft.com/download)

## Local development
To run the app locally:
1. Install the .NET Core SDK development certificate so the app will load over HTTPS ([details](https://docs.microsoft.com/en-us/aspnet/core/security/enforcing-ssl?view=aspnetcore-3.1&tabs=visual-studio#trust-the-aspnet-core-https-development-certificate-on-windows-and-macos)):
```
    dotnet dev-certs https --trust
```

2. Run the app using the `dotnet run` CLI command:
```
    cd dashboard/app
    dotnet run
```
Alternatively, use the `watch` command to update the app upon file changes:
```
    cd dashboard/app
    dotnet watch run
```

3. Visit https://localhost:5001

## Deployment

The app is deployed from [CircleCI](https://app.circleci.com/pipelines/github/18F/piipan). The [configuration](../.circleci/config.yml) is set to deploy to different environments within Azure depending on the branch that triggers the CircleCI job. The basic deploy process is:

1. Build the app
2. Package app as a zip
3. If on a branch that is associated with a deployment, deploy the zip file to the relevant deployment slot in Azure

### Azure deployment slots

The app is configured with three deployment slots when created from the IaC:
- production, the default slot created by App Service (`https://<app_name>.azurewebsites.net/`)
- staging (`https://<app_name>-staging.azurewebsites.net/`)
- develop (`https://<app_name>-develop.azurewebsites.net/`)

The CircleCI configuration associates the following branches with each deployment slot:

| branch | deployment slot |
|---|---|
| `main` | production |
| `staging` | staging |
| `develop` | develop |

A push to any of these branches will be automatically deployed to the associated deployment slot upon a successful build.

### Deployment approach

The app is deployed from CircleCI using the [ZIP deployment method](https://docs.microsoft.com/en-us/azure/app-service/deploy-zip). The app is first built using `dotnet publish -o <build_directory>` and the output is zipped using `cd <build_directory> && zip -r <build_name>.zip .`. Note: the zip file contains the *contents* of the output directory but not the directory itself.

The zip file is then pushed to Azure:

```
    az webapp deployment source config-zip -g <resource_group> -n <app_name> --slot <deployment_slot_name> --src <path_to_build>.zip
```

### Deployment credentials

In order for CircleCI to log in to Azure and run CLI commands we have to supply it with credentials. The credentials are associated with a service principal account that is [created and stored in Azure](https://docs.microsoft.com/en-us/cli/azure/create-an-azure-service-principal-azure-cli#password-based-authentication). Each service principal is issued a client ID, client secret, and tenant ID. Those values are stored as environment variables in Circle CI and accessed by the [circleci/azure-cli orb](https://circleci.com/developer/orbs/orb/circleci/azure-cli) which handles the log in process.