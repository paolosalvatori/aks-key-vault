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

The first step is setting up the name for a new or existing AKS cluster and Azure Key Vault resource in the `scripts/00-variables.sh` file, which is included and used by all the scripts in this sample.

```bash
# Azure Kubernetes Service (AKS)
AKS_NAME="<AKS-Cluster-Name>"
AKS_RESOURCE_GROUP_NAME="<AKS-Resource-Group-Name>"

# Azure Key Vault
KEY_VAULT_NAME="<Key-Vault-name>"
KEY_VAULT_RESOURCE_GROUP_NAME="<Key-Vault-Resource-Group-Name>"
KEY_VAULT_SKU="Standard"
LOCATION="EastUS" # Choose a location

# Secrets and Values 
SECRETS=("username" "password")
VALUES=("admin" "trustno1!")

# Azure Subscription and Tenant
TENANT_ID=$(az account show --query tenantId --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
```

The `SECRETS` array variable contains a list of secrets to create in the Azure Key Vault resource, while the `VALUES` array contains their values. 

### Create or Update AKS Cluster

You can use the following Bash script to create a new AKS cluster with the [az aks create](https://learn.microsoft.com/en-us/cli/azure/aks?view=azure-cli-latest#az-aks-create) command. This script includes the `--enable-oidc-issuer` parameter to enable the [OpenID Connect (OIDC) issuer](https://learn.microsoft.com/en-us/azure/aks/use-oidc-issuer) and the `--enable-workload-identity` parameter to enable [Microsoft Entra Workload ID](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview). If the AKS cluster already exists, the script updates it to use the OIDC issuer and enable workload identity by calling the [az aks update](https://learn.microsoft.com/en-us/cli/azure/aks?view=azure-cli-latest#az-aks-update) command with the same parameters.

```bash
#!/bin/Bash

# Variables
source ../00-variables.sh

# Check if the resource group already exists
echo "Checking if [$AKS_RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_NAME] subscription..."

az group show --name $AKS_RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [$AKS_RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_NAME] subscription"
  echo "Creating [$AKS_RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_NAME] subscription..."

  # create the resource group
  az group create --name $AKS_RESOURCE_GROUP_NAME --location $LOCATION 1>/dev/null

  if [[ $? == 0 ]]; then
    echo "[$AKS_RESOURCE_GROUP_NAME] resource group successfully created in the [$SUBSCRIPTION_NAME] subscription"
  else
    echo "Failed to create [$AKS_RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_NAME] subscription"
    exit
  fi
else
  echo "[$AKS_RESOURCE_GROUP_NAME] resource group already exists in the [$SUBSCRIPTION_NAME] subscription"
fi

# Check if the AKS cluster already exists
echo "Checking if [$AKS_NAME] AKS cluster actually exists in the [$AKS_RESOURCE_GROUP_NAME] resource group..."
az aks show \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --only-show-errors &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [$AKS_NAME] AKS cluster actually exists in the [$AKS_RESOURCE_GROUP_NAME] resource group"
  echo "Creating [$AKS_NAME] AKS cluster in the [$AKS_RESOURCE_GROUP_NAME] resource group..."

  # create the AKS cluster
  az aks create \
    --name $AKS_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --location $LOCATION \
    --enable-oidc-issuer \
    --enable-workload-identity \
    --generate-ssh-keys \
    --only-show-errors &>/dev/null

  if [[ $? == 0 ]]; then
    echo "[$AKS_NAME] AKS cluster successfully created in the [$AKS_RESOURCE_GROUP_NAME] resource group"
  else
    echo "Failed to create [$AKS_NAME] AKS cluster in the [$AKS_RESOURCE_GROUP_NAME] resource group"
    exit
  fi
else
  echo "[$AKS_NAME] AKS cluster already exists in the [$AKS_RESOURCE_GROUP_NAME] resource group"
  
  # Check if the OIDC issuer is enabled in the AKS cluster
  echo "Checking if the OIDC issuer is enabled in the [$AKS_NAME] AKS cluster..."
  oidcEnabled=$(az aks show \
    --name $AKS_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --only-show-errors \
    --query oidcIssuerProfile.enabled \
    --output tsv)

  if [[ $oidcEnabled == "true" ]]; then
    echo "The OIDC issuer is already enabled in the [$AKS_NAME] AKS cluster"
  else
    echo "The OIDC issuer is not enabled in the [$AKS_NAME] AKS cluster"
  fi

  # Check if Workload Identity is enabled in the AKS cluster
  echo "Checking if Workload Identity is enabled in the [$AKS_NAME] AKS cluster..."
  workloadIdentityEnabled=$(az aks show \
    --name $AKS_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --only-show-errors \
    --query securityProfile.workloadIdentity.enabled \
    --output tsv)

  if [[ $workloadIdentityEnabled == "true" ]]; then
    echo "Workload Identity is already enabled in the [$AKS_NAME] AKS cluster"
  else
    echo "Workload Identity is not enabled in the [$AKS_NAME] AKS cluster"
  fi

  # Enable OIDC issuer and Workload Identity
  if [[ $oidcEnabled == "true" && $workloadIdentityEnabled == "true" ]]; then
    echo "OIDC issuer and Workload Identity are already enabled in the [$AKS_NAME] AKS cluster"
    exit
  fi

  echo "Enabling OIDC issuer and Workload Identity in the [$AKS_NAME] AKS cluster..."
  az aks update \
    --name $AKS_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --enable-oidc-issuer \
    --enable-workload-identity \
    --only-show-errors

  if [[ $? == 0 ]]; then
    echo "OIDC issuer and Workload Identity successfully enabled in the [$AKS_NAME] AKS cluster"
  else
    echo "Failed to enable OIDC issuer and Workload Identity in the [$AKS_NAME] AKS cluster"
    exit
  fi
fi
```

### Create or Update Key Vault

You can use the following Bash script to create a new [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/basic-concepts) if it doesn't already exist, and create a couple of secrets for demonstration purposes.

```bash
#!/bin/Bash

# Variables
source ../00-variables.sh

# Check if the resource group already exists
echo "Checking if [$KEY_VAULT_RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_NAME] subscription..."

az group show --name $KEY_VAULT_RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [$KEY_VAULT_RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_NAME] subscription"
  echo "Creating [$KEY_VAULT_RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_NAME] subscription..."

  # create the resource group
  az group create --name $KEY_VAULT_RESOURCE_GROUP_NAME --location $LOCATION 1>/dev/null

  if [[ $? == 0 ]]; then
    echo "[$KEY_VAULT_RESOURCE_GROUP_NAME] resource group successfully created in the [$SUBSCRIPTION_NAME] subscription"
  else
    echo "Failed to create [$KEY_VAULT_RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_NAME] subscription"
    exit
  fi
else
  echo "[$KEY_VAULT_RESOURCE_GROUP_NAME] resource group already exists in the [$SUBSCRIPTION_NAME] subscription"
fi

# Check if the key vault already exists
echo "Checking if [$KEY_VAULT_NAME] key vault actually exists in the [$SUBSCRIPTION_NAME] subscription..."

az keyvault show --name $KEY_VAULT_NAME --resource-group $KEY_VAULT_RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [$KEY_VAULT_NAME] key vault actually exists in the [$SUBSCRIPTION_NAME] subscription"
  echo "Creating [$KEY_VAULT_NAME] key vault in the [$SUBSCRIPTION_NAME] subscription..."

  # create the key vault
  az keyvault create \
    --name $KEY_VAULT_NAME \
    --resource-group $KEY_VAULT_RESOURCE_GROUP_NAME \
    --location $LOCATION \
    --enabled-for-deployment \
    --enabled-for-disk-encryption \
    --enabled-for-template-deployment \
    --sku $KEY_VAULT_SKU 1>/dev/null

  if [[ $? == 0 ]]; then
    echo "[$KEY_VAULT_NAME] key vault successfully created in the [$SUBSCRIPTION_NAME] subscription"
  else
    echo "Failed to create [$KEY_VAULT_NAME] key vault in the [$SUBSCRIPTION_NAME] subscription"
    exit
  fi
else
  echo "[$KEY_VAULT_NAME] key vault already exists in the [$SUBSCRIPTION_NAME] subscription"
fi

# Create secrets
for INDEX in ${!SECRETS[@]}; do
  # Check if the secret already exists
  echo "Checking if [${SECRETS[$INDEX]}] secret actually exists in the [$KEY_VAULT_NAME] key vault..."

  az keyvault secret show --name ${SECRETS[$INDEX]} --vault-name $KEY_VAULT_NAME &>/dev/null

  if [[ $? != 0 ]]; then
    echo "No [${SECRETS[$INDEX]}] secret actually exists in the [$KEY_VAULT_NAME] key vault"
    echo "Creating [${SECRETS[$INDEX]}] secret in the [$KEY_VAULT_NAME] key vault..."

    # create the secret
    az keyvault secret set \
      --name ${SECRETS[$INDEX]} \
      --vault-name $KEY_VAULT_NAME \
      --value ${VALUES[$INDEX]} 1>/dev/null

    if [[ $? == 0 ]]; then
      echo "[${SECRETS[$INDEX]}] secret successfully created in the [$KEY_VAULT_NAME] key vault"
    else
      echo "Failed to create [${SECRETS[$INDEX]}] secret in the [$KEY_VAULT_NAME] key vault"
      exit
    fi
  else
    echo "[${SECRETS[$INDEX]}] secret already exists in the [$KEY_VAULT_NAME] key vault"
  fi
done
```

### Create Managed Identity and Federated Identity Credential

All the techniques use [Microsoft Entra Workload ID](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview). The repository contains a folder for each technique. Each folder includes the following `create-managed-identity.sh` Bash script:

```bash
#/bin/bash

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Check if the resource group already exists
echo "Checking if [$AKS_RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_ID] subscription..."

az group show --name $AKS_RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [$AKS_RESOURCE_GROUP_NAME] resource group actually exists in the [$SUBSCRIPTION_ID] subscription"
  echo "Creating [$AKS_RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_ID] subscription..."

  # create the resource group
  az group create \
    --name $AKS_RESOURCE_GROUP_NAME \
    --location $LOCATION 1>/dev/null

  if [[ $? == 0 ]]; then
    echo "[$AKS_RESOURCE_GROUP_NAME] resource group successfully created in the [$SUBSCRIPTION_ID] subscription"
  else
    echo "Failed to create [$AKS_RESOURCE_GROUP_NAME] resource group in the [$SUBSCRIPTION_ID] subscription"
    exit
  fi
else
  echo "[$AKS_RESOURCE_GROUP_NAME] resource group already exists in the [$SUBSCRIPTION_ID] subscription"
fi

# check if the managed identity already exists
echo "Checking if [$MANAGED_IDENTITY_NAME] managed identity actually exists in the [$AKS_RESOURCE_GROUP_NAME] resource group..."

az identity show \
  --name $MANAGED_IDENTITY_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [$MANAGED_IDENTITY_NAME] managed identity actually exists in the [$AKS_RESOURCE_GROUP_NAME] resource group"
  echo "Creating [$MANAGED_IDENTITY_NAME] managed identity in the [$AKS_RESOURCE_GROUP_NAME] resource group..."

  # create the managed identity
  az identity create \
    --name $MANAGED_IDENTITY_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME &>/dev/null

  if [[ $? == 0 ]]; then
    echo "[$MANAGED_IDENTITY_NAME] managed identity successfully created in the [$AKS_RESOURCE_GROUP_NAME] resource group"
  else
    echo "Failed to create [$MANAGED_IDENTITY_NAME] managed identity in the [$AKS_RESOURCE_GROUP_NAME] resource group"
    exit
  fi
else
  echo "[$MANAGED_IDENTITY_NAME] managed identity already exists in the [$AKS_RESOURCE_GROUP_NAME] resource group"
fi

# Get the managed identity principal id
echo "Retrieving principalId for [$MANAGED_IDENTITY_NAME] managed identity..."
PRINCIPAL_ID=$(az identity show \
  --name $MANAGED_IDENTITY_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query principalId \
  --output tsv)

if [[ -n $PRINCIPAL_ID ]]; then
  echo "[$PRINCIPAL_ID] principalId  or the [$MANAGED_IDENTITY_NAME] managed identity successfully retrieved"
else
  echo "Failed to retrieve principalId for the [$MANAGED_IDENTITY_NAME] managed identity"
  exit
fi

# Get the managed identity client id
echo "Retrieving clientId for [$MANAGED_IDENTITY_NAME] managed identity..."
CLIENT_ID=$(az identity show \
  --name $MANAGED_IDENTITY_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query clientId \
  --output tsv)

if [[ -n $CLIENT_ID ]]; then
  echo "[$CLIENT_ID] clientId  for the [$MANAGED_IDENTITY_NAME] managed identity successfully retrieved"
else
  echo "Failed to retrieve clientId for the [$MANAGED_IDENTITY_NAME] managed identity"
  exit
fi

# Retrieve the resource id of the Key Vault resource
echo "Retrieving the resource id for the [$KEY_VAULT_NAME] key vault..."
KEY_VAULT_ID=$(az keyvault show \
  --name $KEY_VAULT_NAME \
  --resource-group $KEY_VAULT_RESOURCE_GROUP_NAME \
  --query id \
  --output tsv)

if [[ -n $KEY_VAULT_ID ]]; then
  echo "[$KEY_VAULT_ID] resource id for the [$KEY_VAULT_NAME] key vault successfully retrieved"
else
  echo "Failed to retrieve the resource id for the [$KEY_VAULT_NAME] key vault"
  exit
fi

# Assign the Key Vault Secrets User role to the managed identity with Key Vault as a scope
ROLE="Key Vault Secrets User"
echo "Checking if [$ROLE] role with [$KEY_VAULT_NAME] key vault as a scope is already assigned to the [$MANAGED_IDENTITY_NAME] managed identity..."
CURRENT_ROLE=$(az role assignment list \
  --assignee $PRINCIPAL_ID \
  --scope $KEY_VAULT_ID \
  --query "[?roleDefinitionName=='$ROLE'].roleDefinitionName" \
  --output tsv 2>/dev/null)

if [[ $CURRENT_ROLE == $ROLE ]]; then
  echo "[$ROLE] role with [$KEY_VAULT_NAME] key vault as a scope is already assigned to the [$MANAGED_IDENTITY_NAME] managed identity"
else
  echo "[$ROLE] role with [$KEY_VAULT_NAME] key vault as a scope is not assigned to the [$MANAGED_IDENTITY_NAME] managed identity"
  echo "Assigning the [$ROLE] role with [$KEY_VAULT_NAME] key vault as a scope to the [$MANAGED_IDENTITY_NAME] managed identity..."

  for i in {1..10}; do
    az role assignment create \
      --assignee $PRINCIPAL_ID \
      --role "$ROLE" \
      --scope $KEY_VAULT_ID 1>/dev/null

    if [[ $? == 0 ]]; then
      echo "Successfully assigned the [$ROLE] role with [$KEY_VAULT_NAME] key vault as a scope to the [$MANAGED_IDENTITY_NAME] managed identity"
      break
    else
      echo "Failed to assign the [$ROLE] role with [$KEY_VAULT_NAME] key vault as a scope to the [$MANAGED_IDENTITY_NAME] managed identity, retrying in 5 seconds..."
      sleep 5
    fi

    if [[ $i == 3 ]]; then
      echo "Failed to assign the [$ROLE] role with [$KEY_VAULT_NAME] key vault as a scope to the [$MANAGED_IDENTITY_NAME] managed identity after 3 attempts"
      exit
    fi
  done
fi

# Check if the namespace exists in the cluster
RESULT=$(kubectl get namespace -o 'jsonpath={.items[?(@.metadata.name=="'$NAMESPACE'")].metadata.name'})

if [[ -n $RESULT ]]; then
  echo "[$NAMESPACE] namespace already exists in the cluster"
else
  echo "[$NAMESPACE] namespace does not exist in the cluster"
  echo "Creating [$NAMESPACE] namespace in the cluster..."
  kubectl create namespace $NAMESPACE
fi

# Check if the service account already exists
RESULT=$(kubectl get sa -n $NAMESPACE -o 'jsonpath={.items[?(@.metadata.name=="'$SERVICE_ACCOUNT_NAME'")].metadata.name'})

if [[ -n $RESULT ]]; then
  echo "[$SERVICE_ACCOUNT_NAME] service account already exists"
else
  # Create the service account
  echo "[$SERVICE_ACCOUNT_NAME] service account does not exist"
  echo "Creating [$SERVICE_ACCOUNT_NAME] service account..."
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: $CLIENT_ID
    azure.workload.identity/tenant-id: $TENANT_ID
  labels:
    azure.workload.identity/use: "true"
  name: $SERVICE_ACCOUNT_NAME
  namespace: $NAMESPACE
EOF
fi

# Show service account YAML manifest
echo "Service Account YAML manifest"
echo "-----------------------------"
kubectl get sa $SERVICE_ACCOUNT_NAME -n $NAMESPACE -o yaml

# Check if the federated identity credential already exists
echo "Checking if [$FEDERATED_IDENTITY_NAME] federated identity credential actually exists in the [$AKS_RESOURCE_GROUP_NAME] resource group..."

az identity federated-credential show \
  --name $FEDERATED_IDENTITY_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --identity-name $MANAGED_IDENTITY_NAME &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [$FEDERATED_IDENTITY_NAME] federated identity credential actually exists in the [$AKS_RESOURCE_GROUP_NAME] resource group"

  # Get the OIDC Issuer URL
  AKS_OIDC_ISSUER_URL="$(az aks show \
    --only-show-errors \
    --name $AKS_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --query oidcIssuerProfile.issuerUrl \
    --output tsv)"

  # Show OIDC Issuer URL
  if [[ -n $AKS_OIDC_ISSUER_URL ]]; then
    echo "The OIDC Issuer URL of the [$AKS_NAME] cluster is [$AKS_OIDC_ISSUER_URL]"
  fi

  echo "Creating [$FEDERATED_IDENTITY_NAME] federated identity credential in the [$AKS_RESOURCE_GROUP_NAME] resource group..."

  # Establish the federated identity credential between the managed identity, the service account issuer, and the subject.
  az identity federated-credential create \
    --name $FEDERATED_IDENTITY_NAME \
    --identity-name $MANAGED_IDENTITY_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --issuer $AKS_OIDC_ISSUER_URL \
    --subject system:serviceaccount:$NAMESPACE:$SERVICE_ACCOUNT_NAME

  if [[ $? == 0 ]]; then
    echo "[$FEDERATED_IDENTITY_NAME] federated identity credential successfully created in the [$AKS_RESOURCE_GROUP_NAME] resource group"
  else
    echo "Failed to create [$FEDERATED_IDENTITY_NAME] federated identity credential in the [$AKS_RESOURCE_GROUP_NAME] resource group"
    exit
  fi
else
  echo "[$FEDERATED_IDENTITY_NAME] federated identity credential already exists in the [$AKS_RESOURCE_GROUP_NAME] resource group"
fi
```

The Bash script performs the following steps:

- It sources variables from two files: `../00-variables.sh` and `./00-variables.sh`.
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

Run the following Bash script to upgrade your AKS cluster with the [Azure Key Vault provider for Secrets Store CSI Driver](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver) capability using the [az aks enable-addons](https://learn.microsoft.com/en-us/cli/azure/aks#az-aks-enable-addons) command to enable the `azure-keyvault-secrets-provider` add-on. The add-on creates a user-assigned managed identity you can use to authenticate to your key vault. Alternatively, you can use a bring-your-own user-assigned managed identity.

```bash
#!/bin/bash

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Enable Addon
echo "Checking if the [azure-keyvault-secrets-provider] addon is enabled in the [$AKS_NAME] AKS cluster..."
az aks addon show \
  --addon azure-keyvault-secrets-provider \
  --name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME &>/dev/null

if [[ $? != 0 ]]; then
  echo "The [azure-keyvault-secrets-provider] addon is not enabled in the [$AKS_NAME] AKS cluster"
  echo "Enabling the [azure-keyvault-secrets-provider] addon in the [$AKS_NAME] AKS cluster..."

  az aks addon enable \
    --addon azure-keyvault-secrets-provider \
    --enable-secret-rotation \
    --name $AKS_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME
else
  echo "The [azure-keyvault-secrets-provider] addon is already enabled in the [$AKS_NAME] AKS cluster"
fi
```

You can create a user-assigned managed identity for the workload, create federated credentials, and assign the proper permissions to it to read secrets from the source Key Vault using the [create-managed-identity.sh](#create-managed-identity-and-federated-identity-credential) Bash script. The next step is creating an instance of the [SecretProviderClass](https://learn.microsoft.com/en-us/azure/aks/aksarc/secrets-store-csi-driver#create-and-apply-your-own-secretproviderclass-object) custom resource in your workload namespace. The `SecretProviderClass` is a namespaced resource in Secrets Store CSI Driver that is used to provide driver configurations and provider-specific parameters to the CSI driver. The `SecretProviderClass` allows you to indicate the client ID of a user-assigned managed identity used to read secret material from Key Vault, and the list of secrets, keys, and certificates to read from Key Vault. For each object, you can optionally indicate an alternative name or alias using the `objectAlias` property. In this case, the driver will create a file with the alias as the name. You can even indicate a specific version of a secret, key, or certificate. You can retrieve the latest version just by assigning the `objectVersion` the null value or empty string.

```bash
#/bin/bash

# For more information, see:
# https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver
# https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Get the managed identity client id
echo "Retrieving clientId for [$MANAGED_IDENTITY_NAME] managed identity..."
CLIENT_ID=$(az identity show \
  --name $MANAGED_IDENTITY_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --query clientId \
  --output tsv)

if [[ -n $CLIENT_ID ]]; then
  echo "[$CLIENT_ID] clientId  for the [$MANAGED_IDENTITY_NAME] managed identity successfully retrieved"
else
  echo "Failed to retrieve clientId for the [$MANAGED_IDENTITY_NAME] managed identity"
  exit
fi

# Create the SecretProviderClass for the secret store CSI driver with Azure Key Vault provider
echo "Creating the SecretProviderClass for the secret store CSI driver with Azure Key Vault provider..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name:  $SECRET_PROVIDER_CLASS_NAME
spec:
  provider: azure
  parameters:
    clientID: "$CLIENT_ID"
    keyvaultName: "$KEY_VAULT_NAME"
    tenantId: "$TENANT_ID"
    objects:  |
      array:
        - |
          objectName: username
          objectAlias: username
          objectType: secret        
          objectVersion: ""
        - |
          objectName: password
          objectAlias: password
          objectType: secret
          objectVersion: ""
EOF
```

The Bash script creates a `SecretProviderClass` custom resource configured to read the latest value of the `username` and `password` secrets from the source Key Vault. You can now use the following Bash script to deploy the sample application.

```bash
#/bin/bash

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Create the pod
echo "Creating the [$POD_NAME] pod in the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
kind: Pod
apiVersion: v1
metadata:
  name: $POD_NAME
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: $SERVICE_ACCOUNT_NAME
  containers:
    - name: nginx
      image: nginx
      resources:
        requests:
          memory: "32Mi"
          cpu: "50m"
        limits:
          memory: "64Mi"
          cpu: "100m"
      volumeMounts:
        - name: secrets-store
          mountPath: "/mnt/secrets"
          readOnly: true
  volumes:
    - name: secrets-store
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "$SECRET_PROVIDER_CLASS_NAME"
EOF
```

The YAML manifest contains a volume definition called `secrets-store` that uses the [secrets-store.csi.k8s.io](https://secrets-store-csi-driver.sigs.k8s.io/) Secrets Store CSI Driver and references the `SecretProviderClass` resource created in the previous step by name. The YAML configuration defines a `Pod` with a container named `nginx` that mounts the `secrets-store` volume in read-only mode. On pod start and restart, the driver will communicate with the provider using gRPC to retrieve the secret content from the Key Vault resource you have specified in the `SecretProviderClass` custom resource.

You can run the following Bash script to print the value of each files, one for each secret specified in the `SecretProviderClass` custom resource, from the `/mnt/secrets` mounted volume.

```bash
#!/bin/bash

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Check if the pod exists
POD=$(kubectl get pod $POD_NAME -n $NAMESPACE -o 'jsonpath={.metadata.name}')

if [[ -z $POD ]]; then
    echo "No [$POD_NAME] pod found in [$NAMESPACE] namespace."
    exit
fi

# List secrets from /mnt/secrets volume
echo "Reading files from [/mnt/secrets] volume in [$POD_NAME] pod..."
FILES=$(kubectl exec $POD -n $NAMESPACE -- ls /mnt/secrets)

# Retrieve secrets from /mnt/secrets volume
for FILE in ${FILES[@]}
do
    echo "Retrieving [$FILE] secret from [$KEY_VAULT_NAME] key vault..."
    kubectl exec $POD --stdin --tty -n $NAMESPACE -- cat /mnt/secrets/$FILE;echo;sleep 1
done 
```

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
