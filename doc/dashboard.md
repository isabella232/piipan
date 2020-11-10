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
Optionally, use the `watch` command to update the app upon changes to files:
```
    cd dashboard/app
    dotnet watch run
```
3. Visit https://localhost:5001