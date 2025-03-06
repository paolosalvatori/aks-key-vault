# Azure Key Vault Provider for Secrets Store CSI Driver in AKS

## Overview

The [Azure Key Vault provider for Secrets Store CSI Driver](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver) enables retrieving secrets, keys, and certificates stored in Azure Key Vault and accessing them as files from mounted volumes in an AKS cluster. This method eliminates the need for Azure-specific libraries to access the secrets.

This [Secret Store CSI Driver for Key Vault](https://github.com/Azure/secrets-store-csi-driver-provider-azure) offers the following features:

- Mounts secrets, keys, and certificates to a pod using a CSI volume.
- Supports CSI inline volumes.
- Allows the mounting of multiple secrets store objects as a single volume.
- Offers pod portability with the SecretProviderClass CRD.
- Compatible with Windows containers.
- Keeps in sync with Kubernetes secrets.
- Supports auto-rotation of mounted contents and synced Kubernetes secrets.

When auto-rotation is enabled for the Azure Key Vault Secrets Provider, it automatically updates both the pod mount and the corresponding Kubernetes secret defined in the **secretObjects** field of SecretProviderClass. It continuously polls for changes based on the rotation poll interval (default is two minutes).

If a secret in an external secrets store is updated after the initial deployment of the pod, both the Kubernetes Secret and the pod mount will periodically update, depending on how the application consumes the secret data. Here are the recommended approaches for different scenarios:

1. Mount the Kubernetes Secret as a volume: Utilize the auto-rotation and sync K8s secrets features of Secrets Store CSI Driver. The application should monitor changes from the mounted Kubernetes Secret volume. When the CSI Driver updates the Kubernetes Secret, the volume contents will be automatically updated.
2. Application reads data from the container filesystem: Take advantage of the rotation feature of Secrets Store CSI Driver. The application should monitor file changes from the volume mounted by the CSI driver.
3. Use the Kubernetes Secret for an environment variable: Restart the pod to acquire the latest secret as an environment variable. You can use tools like Reloader to watch for changes on the synced Kubernetes Secret and perform rolling upgrades on pods.

### Advantages

- Secrets, keys, and certificates can be accessed as files from mounted volumes.
- Optionally, Kubernetes secrets can be created to store keys, secrets, and certificates from Key Vault.
- No need for Azure-specific libraries to access secrets.
- Simplifies secret management with transparent integration.

### Disadvantages

- Still requires accessing managed services such as Azure Service Bus or Azure Storage using their own connection strings from Azure Key Vault.
- Cannot utilize Microsoft Entra ID integrated security and managed identities for accessing managed services.

## Hands-On Lab Prerequisites

### Configure Variables

The first step is setting up the name for a new or existing AKS cluster and Azure Key Vault resource in the [`scripts/00-variables.sh`](../../scripts/00-variables.sh) file, which is included and used by all the scripts in this sample.

The `SECRETS` array variable contains a list of secrets to create in the Azure Key Vault resource, while the `VALUES` array contains their values. 

### Create or Update AKS Cluster

You can use Bash script, [`01-create-or-update-aks.sh`](../../scripts/prerequisites/01-create-or-update-aks.sh), to create a new AKS cluster with the [az aks create](https://learn.microsoft.com/en-us/cli/azure/aks?view=azure-cli-latest#az-aks-create) command. This script includes the `--enable-oidc-issuer` parameter to enable the [OpenID Connect (OIDC) issuer](https://learn.microsoft.com/en-us/azure/aks/use-oidc-issuer) and the `--enable-workload-identity` parameter to enable [Microsoft Entra Workload ID](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview). If the AKS cluster already exists, the script updates it to use the OIDC issuer and enable workload identity by calling the [az aks update](https://learn.microsoft.com/en-us/cli/azure/aks?view=azure-cli-latest#az-aks-update) command with the same parameters.

### Create or Update Key Vault

You can use Bash script, [`02-create-key-vault-and-secrets.sh`](../../scripts/prerequisites/02-create-key-vault-and-secrets.sh), to create a new [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/basic-concepts) if it doesn't already exist, and create a couple of secrets for demonstration purposes.

### Create Managed Identity and Federated Identity Credential

All the techniques use [Microsoft Entra Workload ID](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview). The repository contains a folder for each technique. Each folder includes Bash script, [`create-managed-identity.sh`](../../scripts/key-vault-csi-driver/02-create-managed-identity.sh).

The Bash script performs the following steps:

- It sources variables from two files: [`scripts/00-variables.sh`](../../scripts/00-variables.sh) and [`scripts/key-vault-csi-driver/00-variables.sh`](../../scripts/key-vault-csi-driver/00-variables.sh) .
- It checks if the specified resource group exists. If not, it creates the resource group.
- It checks if the specified managed identity exists within the resource group. If not, it creates a user-assigned managed identity.
- It retrieves the `principalId` and `clientId` of the managed identity.
- It retrieves the `id` of the Azure Key Vault resource.
- It assigns the `Key Vault Secrets User` role to the managed identity with the Azure Key Vault as the scope.
- It checks if the specified Kubernetes namespace exists. If not, it creates the namespace.
- It checks if a specified Kubernetes service account exists within the namespace. If not, it creates the service account with the annotations and labels required by [Microsoft Entra Workload ID](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview).
- It checks if a specified federated identity credential exists within the resource group. If not, it retrieves the OIDC Issuer URL of the specified AKS cluster and creates the federated identity credential.

## Hands-On Lab: Azure Key Vault Provider for Secrets Store CSI Driver in AKS

The Secrets Store Container Storage Interface (CSI) Driver on Azure Kubernetes Service (AKS) provides various methods of identity-based access to your Azure Key Vault. You can use one of the following access methods:

- [Service Connector with managed identity](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access?tabs=azure-portal&pivots=access-with-service-connector#create-a-service-connection-in-aks-with-service-connector)
- [Workload ID](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access?tabs=azure-portal&pivots=access-with-a-microsoft-entra-workload-identity#create-a-service-connection-in-aks-with-service-connector)
- [User-assigned managed identity](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access?tabs=azure-portal&pivots=access-with-a-user-assigned-managed-identity#create-a-service-connection-in-aks-with-service-connector)

This article outlines focus on the [Workload ID](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access?tabs=azure-portal&pivots=access-with-a-microsoft-entra-workload-identity#create-a-service-connection-in-aks-with-service-connector) option. Please see the documentantion for the other methods.

Run Bash script, [`01-enable-addon.sh`](../../scripts/key-vault-csi-driver/01-enable-addon.sh), to upgrade your AKS cluster with the [Azure Key Vault provider for Secrets Store CSI Driver](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver) capability using the [az aks enable-addons](https://learn.microsoft.com/en-us/cli/azure/aks#az-aks-enable-addons) command to enable the `azure-keyvault-secrets-provider` add-on. The add-on creates a user-assigned managed identity you can use to authenticate to your key vault. Alternatively, you can use a bring-your-own user-assigned managed identity.

You can create a user-assigned managed identity for the workload, create federated credentials, and assign the proper permissions to it to read secrets from the source Key Vault using the [`02-create-managed-identity.sh`](../../scripts/key-vault-csi-driver/02-create-managed-identity.sh) Bash script. The next step is creating an instance of the [SecretProviderClass](https://learn.microsoft.com/en-us/azure/aks/aksarc/secrets-store-csi-driver#create-and-apply-your-own-secretproviderclass-object) custom resource in your workload namespace using Bash script, [`03-create-secret-provider-class.sh`](../../scripts/key-vault-csi-driver/03-create-secret-provider-class.sh). The `SecretProviderClass` is a namespaced resource in Secrets Store CSI Driver that is used to provide driver configurations and provider-specific parameters to the CSI driver. The `SecretProviderClass` allows you to indicate the client ID of a user-assigned managed identity used to read secret material from Key Vault, and the list of secrets, keys, and certificates to read from Key Vault. For each object, you can optionally indicate an alternative name or alias using the `objectAlias` property. In this case, the driver will create a file with the alias as the name. You can even indicate a specific version of a secret, key, or certificate. You can retrieve the latest version just by assigning the `objectVersion` the null value or empty string.

The Bash script creates a `SecretProviderClass` custom resource configured to read the latest value of the `username` and `password` secrets from the source Key Vault. You can now use Bash script, [`04-create-demo-pod.sh`](../../scripts/key-vault-csi-driver/04-create-demo-pod.sh), to deploy the sample application.

The YAML manifest contains a volume definition called `secrets-store` that uses the [secrets-store.csi.k8s.io](https://secrets-store-csi-driver.sigs.k8s.io/) Secrets Store CSI Driver and references the `SecretProviderClass` resource created in the previous step by name. The YAML configuration defines a `Pod` with a container named `nginx` that mounts the `secrets-store` volume in read-only mode. On pod start and restart, the driver will communicate with the provider using gRPC to retrieve the secret content from the Key Vault resource you have specified in the `SecretProviderClass` custom resource.

You can run Bash Script, [`05-list-secrets.sh`](../../scripts/key-vault-csi-driver/05-list-secrets.sh), to print the value of each files, one for each secret specified in the `SecretProviderClass` custom resource, from the `/mnt/secrets` mounted volume.

## Conclusion

[Azure Key Vault provider for Secrets Store CSI Driver](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver) can be summarized as follows:
  - Secrets, keys, and certificates can be accessed as files from mounted volumes.
  - Optionally, Kubernetes secrets can be created to store keys, secrets, and certificates from Key Vault.
  - No need for Azure-specific libraries to access secrets.
  - Simplifies secret management with transparent integration.

## Resources

- [Using the Azure Key Vault Provider for Secrets Store CSI Driver in AKS](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)
- [Access Azure Key Vault with the CSI Driver Identity Provider](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access?tabs=azure-portal&pivots=access-with-service-connector)
- [Configuration and Troubleshooting Options for Azure Key Vault Provider in AKS](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-configuration-options)
- [Azure Key Vault Provider for Secrets Store CSI Driver](https://github.com/Azure/secrets-store-csi-driver-provider-azure)
