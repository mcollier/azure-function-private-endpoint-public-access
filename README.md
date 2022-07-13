# Private Azure Function with Public Access

This is a **sample** to enable public Internet access for an Azure Function Premium app with a virtual network private endpoint.

## Getting Started

This repo is enabled to use the [Azure Developer CLI](https://github.com/Azure/azure-dev).

1. Install the Azure Developer CLI
1. Use the Azure Developer CLI to get a local copy of the repo.

    ```shell
    azd init --template mcollier/azure-function-private-endpoint-public-access
    ```

1. When prompted, provide a name for the environment, select the Azure region, and select your Azure subscription.
1. Create two new environment variables for the Virtual Machine admin username and password.

    ```shell
    azd env set AZURE_VM_ADMIN_USERNAME [YOUR-USERNAME]
    azd env set AZURE_VM_ADMIN_PASSWORD [YOUR-PASSWORD]
    ```

1. Provision the Azure resources.

    ```shell
    azd provision
    ```
