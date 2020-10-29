# Infrastructure-as-Code

## Prerequisites
- [Azure Command Line Interface (CLI)](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- `bash` shell

## Steps
To (re)create the Azure resources that `piipan` uses:
1. Sign in with the Azure CLI `login` command :
```
    az login
```
2. Run `create-resources`:
```
    cd iac
    ./create-resources.sh
```
## Notes
- `iac/states.csv` contains the comma-delimited records of participating states/territories. The first field is the [two-leter postal abbreviation](https://pe.usps.com/text/pub28/28apb.htm); the second field is the name of the state/territory.
- For development, dummy state/territories are used (e.g., the state of `Echo Alpha`, with an abbreviation of `EA`).