# Infrastructure-as-Code

## Prerequisites
- [Azure Command Line Interface (CLI)](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- `bash` shell, `/dev/urandom`, etc. via macOS, Linux, or the Windows Subsystem for Linux (WSL) 

## Steps
To (re)create the Azure resources that `piipan` uses:
1. Connect to a trusted network. Currently, only the GSA network block is trusted.
2. Sign in with the Azure CLI `login` command :
```
    az login
```
3. Run `create-resources`, which deploys Azure Resource Manager (ARM) templates and runs associated scripts:
```
    cd iac
    ./create-resources.bash
```
## Notes
- `iac/states.csv` contains the comma-delimited records of participating states/territories. The first field is the [two-leter postal abbreviation](https://pe.usps.com/text/pub28/28apb.htm); the second field is the name of the state/territory.
- For development, dummy state/territories are used (e.g., the state of `Echo Alpha`, with an abbreviation of `EA`).
- Multiple PostgreSQL databases cannot be created with an ARM template. Instead the PostgreSQL server must be accessed from a trusted network (as established by its ARM template firewall variable), and Data Definition Language (DDL) scripts must be applied.
