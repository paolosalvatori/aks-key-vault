# Dapr Secret Store for Key Vault

## Overview

[Dapr (Distributed Application Runtime)](https://docs.dapr.io/concepts/overview/) is a versatile and event-driven runtime that simplifies the development of resilient, stateless, and stateful applications for both cloud and edge environments. It embraces the diversity of programming languages and developer frameworks, providing a seamless experience regardless of your preferences. Dapr encapsulates the best practices for building microservices into a set of open and independent APIs known as building blocks. These building blocks offer the following capabilities:

1. Enable developers to build portable applications using their preferred language and framework.
2. Are completely independent from each other, allowing flexibility and freedom of choice.
3. Have no limits on how many building blocks can be used within an application.

Dapr offers a built-in [secrets building block](https://docs.dapr.io/developing-applications/building-blocks/secrets/secrets-overview/) that makes it easier for developers to consume application secrets from a secret store such as Azure Key Vault, AWS Secret Manager, and Google Key Management, and Hashicorp Vault.

![Dapr secrets building block](./images/secrets-overview-azure-aks-keyvault.png)

You can follow these steps to use Dapr's secret store building block:

1. Deploy the Dapr extension to your AKS cluster.
2. Set up a component for a specific secret store solution.
3. Retrieve secrets using the Dapr secrets API in your application code.
4. Optionally, reference secrets in Dapr component files.

You can watch [this overview video and demo](https://www.youtube.com/live/0y7ne6teHT4?si=3bmNSSyIEIVSF-Ej&t=9931) to see how Dapr secrets management works.

The secrets management API building block offers several features for your application.

- **Configure secrets without changing application code**: You can call the secrets API in your application code to retrieve and use secrets from Dapr-supported secret stores. Watch [this video](https://www.youtube.com/watch?v=OtbYCBt9C34&t=1818) for an example of how the secrets management API can be used in your application.
- **Reference secret stores in Dapr components**: When configuring Dapr components like state stores, you often need to include credentials in component files. Alternatively, you can place the credentials within a Dapr-supported secret store and reference the secret within the Dapr component. This approach is recommended, especially in production environments. Read more about [referencing secret stores in components](https://docs.dapr.io/operations/components/component-secrets/).
- **Limit access to secrets**: Dapr provides the ability to define scopes and restrict access permissions to provide more granular control over access to secrets. Learn more about [using secret scoping](https://docs.dapr.io/developing-applications/building-blocks/secrets/secrets-scopes/).

### Advantages

- Allows applications to retrieve secrets from various secret stores, including Azure Key Vault.
- Simplifies secret management with Dapr's consistent API.
- Supports Azure Key Vault integration with managed identities.
- Supports third-party secret stores, such as Azure Key Vault, AWS Secret Manager, and Google Key Management, and Hashicorp Vault.

### Disadvantages

- Requires injecting a sidecar container for Dapr into the pod, which may not be suitable for all scenarios.

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

## Hands-On Lab: Dapr Secret Store for Key Vault

[Distributed Application Runtime (Dapr)](https://docs.dapr.io/concepts/overview/) is is a versatile and event-driven runtime that can help you write and implement simple, portable, resilient, and secured microservices. Dapr works together with Kubernetes clusters such as [Azure Kubernetes Services (AKS)](https://learn.microsoft.com/en-us/azure/aks/what-is-aks) and [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/overview) as an abstraction layer to provide a low-maintenance and scalable platform.

The first step is running the following script to check if Dapr is actually installed on your AKS cluster, and if not, install the Dapr extension. For more information, see [Install the Dapr extension for Azure Kubernetes Service (AKS) and Arc-enabled Kubernetes](https://learn.microsoft.com/en-us/azure/aks/dapr?tabs=cli).

```bash
#!/bin/bash

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Install AKS cluster extension in your Azure subscription
echo "Check if the [k8s-extension] is already installed in the [$SUBSCRIPTION_NAME] subscription..."
az extension show --name k8s-extension &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [k8s-extension] extension actually exists in the [$SUBSCRIPTION_NAME] subscription"
  echo "Installing [k8s-extension] extension in the [$SUBSCRIPTION_NAME] subscription..."

  # install the extension
  az extension add --name k8s-extension

  if [[ $? == 0 ]]; then
    echo "[k8s-extension] extension successfully installed in the [$SUBSCRIPTION_NAME] subscription"
  else
    echo "Failed to install [k8s-extension] extension in the [$SUBSCRIPTION_NAME] subscription"
    exit
  fi
else
  echo "[k8s-extension] extension already exists in the [$SUBSCRIPTION_NAME] subscription"
fi

# Checking if the the KubernetesConfiguration resource provider is registered in your Azure subscription
echo "Checking if the [Microsoft.KubernetesConfiguration] resource provider is already registered in the [$SUBSCRIPTION_NAME] subscription..."
az provider show --namespace Microsoft.KubernetesConfiguration &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [Microsoft.KubernetesConfiguration] resource provider actually exists in the [$SUBSCRIPTION_NAME] subscription"
  echo "Registering [Microsoft.KubernetesConfiguration] resource provider in the [$SUBSCRIPTION_NAME] subscription..."

  # register the resource provider
  az provider register --namespace Microsoft.KubernetesConfiguration

  if [[ $? == 0 ]]; then
    echo "[Microsoft.KubernetesConfiguration] resource provider successfully registered in the [$SUBSCRIPTION_NAME] subscription"
  else
    echo "Failed to register [Microsoft.KubernetesConfiguration] resource provider in the [$SUBSCRIPTION_NAME] subscription"
    exit
  fi
else
  echo "[Microsoft.KubernetesConfiguration] resource provider already exists in the [$SUBSCRIPTION_NAME] subscription"
fi

# Check if the ExtenstionTypes feature is registered in your Azure subscription
echo "Checking if the [ExtensionTypes] feature is already registered in the [Microsoft.KubernetesConfiguration] namespace..."
az feature show --namespace Microsoft.KubernetesConfiguration --name ExtensionTypes &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [ExtensionTypes] feature actually exists in the [Microsoft.KubernetesConfiguration] namespace"
  echo "Registering [ExtensionTypes] feature in the [Microsoft.KubernetesConfiguration] namespace..."

  # register the feature
  az feature register --namespace Microsoft.KubernetesConfiguration --name ExtensionTypes

  if [[ $? == 0 ]]; then
    echo "[ExtensionTypes] feature successfully registered in the [Microsoft.KubernetesConfiguration] namespace"
  else
    echo "Failed to register [ExtensionTypes] feature in the [Microsoft.KubernetesConfiguration] namespace"
    exit
  fi
else
  echo "[ExtensionTypes] feature already exists in the [Microsoft.KubernetesConfiguration] namespace"
fi

# Check if Dapr extension is installed on your AKS cluster
echo "Checking if the [Dapr] extension is already installed on the [$AKS_NAME] AKS cluster..."
az k8s-extension show \
  --name dapr \
  --cluster-name $AKS_NAME \
  --resource-group $AKS_RESOURCE_GROUP_NAME \
  --cluster-type managedClusters &>/dev/null

if [[ $? != 0 ]]; then
  echo "No [Dapr] extension actually exists on the [$AKS_NAME] AKS cluster"
  echo "Installing [Dapr] extension on the [$AKS_NAME] AKS cluster..."

  # install the extension
  az k8s-extension create \
    --name dapr \
    --cluster-name $AKS_NAME \
    --resource-group $AKS_RESOURCE_GROUP_NAME \
    --cluster-type managedClusters \
    --extension-type "Microsoft.Dapr" \
    --scope cluster \
    --release-namespace "dapr-system"

  if [[ $? == 0 ]]; then
    echo "[Dapr] extension successfully installed on the [$AKS_NAME] AKS cluster"
  else
    echo "Failed to install [Dapr] extension on the [$AKS_NAME] AKS cluster"
    exit
  fi
else
  echo "[Dapr] extension already exists on the [$AKS_NAME] AKS cluster"
fi
```

You can create a user-assigned managed identity for the workload, create federated credentials, and assign the proper permissions to it to read secrets from the source Key Vault using the [create-managed-identity.sh](#create-managed-identity-and-federated-identity-credential) Bash script. Then, you can run the following Bash script to retrieve the `clientId` for the user-assigned managed identity used to access Key Vault and create a Dapr secret store component for the secret store CSI driver with Azure Key Vault provider. The YAML manifest of the Dapr component assigns the following values to the component metadata:

- Key Vault name to the `vaultName` attribute.
- Client id of the user-assigned managed identity to the `azureClientId` attribute.

```bash
#!/bin/bash

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

# Create the Dapr secret store for Azure Key Vault
echo "Creating the secret store for [$KEY_VAULT_NAME] Azure Key Vault..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: $SECRET_STORE_NAME
spec:
  type: secretstores.azure.keyvault
  version: v1
  metadata:
  - name: vaultName
    value: ${KEY_VAULT_NAME,,}
  - name: azureClientId
    value: $CLIENT_ID
EOF
```

The next step is deploying the demo application using the following Bash script. The service account used by the Kubernetes deployment is federated with the user-assigned managed identity. Aldo note that the deployment is configured to use Dapr via the following Kubernetes annotations:

- `dapr.io/app-id`: The unique ID of the application. Used for service discovery, state encapsulation and the pub/sub consumer ID.
- `dapr.io/enabled`: Setting this paramater to true injects the Dapr sidecar into the pod.
- `dapr.io/app-port`: This parameter tells Dapr which port your application is listening on.

For more information on Dapr annotations, see [Dapr arguments and annotations for daprd, CLI, and Kubernetes](https://docs.dapr.io/reference/arguments-annotations-overview/).

```bash
#!/bin/bash

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Check if the namespace exists in the cluster
RESULT=$(kubectl get namespace -o 'jsonpath={.items[?(@.metadata.name=="'$NAMESPACE'")].metadata.name'})

if [[ -n $RESULT ]]; then
  echo "[$NAMESPACE] namespace already exists in the cluster"
else
  echo "[$NAMESPACE] namespace does not exist in the cluster"
  echo "Creating [$NAMESPACE] namespace in the cluster..."
  kubectl create namespace $NAMESPACE
fi

# Create deployment
echo "Creating [$APP_NAME] deployment in the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
kind: Deployment
apiVersion: apps/v1
metadata:
  name: $APP_NAME
  labels:
    app: $APP_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP_NAME
      azure.workload.identity/use: "true"
  template:
    metadata:
      labels:
        app: $APP_NAME
        azure.workload.identity/use: "true"
      annotations:
        dapr.io/enabled: "true"
        dapr.io/app-id: "$APP_NAME"
        dapr.io/app-port: "80"
    spec:
      serviceAccountName: $SERVICE_ACCOUNT_NAME
      containers:
      - name: nginx
        image: nginx
        imagePullPolicy: Always
        ports:
          - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
EOF
```

You can run the following Bash script to connect to the demo pod and print out the value of the two sample secrets stored in Key Vault.

```bash
#!/bin/bash

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Get pod name
POD=$(kubectl get pod -n $NAMESPACE -o 'jsonpath={.items[].metadata.name}')

if [[ -z $POD ]]; then
    echo 'no pod found, please check the name of the deployment and namespace'
    exit
fi

# List secrets from /mnt/secrets volume       
for SECRET in ${SECRETS[@]}
do
    echo "Retrieving [$SECRET] secret from [$KEY_VAULT_NAME] key vault..."
    json=$(kubectl exec --stdin --tty -n $NAMESPACE -c $CONTAINER $POD \
        -- curl http://localhost:3500/v1.0/secrets/key-vault-secret-store/$SECRET;echo)
    echo $json | jq .
done
```

## Conclusion

[Dapr Secret Store for Key Vault](https://docs.dapr.io/developing-applications/building-blocks/secrets/secrets-overview/) can be summarized as follows:
  - Allows applications to retrieve secrets from various secret stores, including Azure Key Vault.
  - Simplifies secret management with Dapr's consistent API.
  - Supports Azure Key Vault integration with managed identities.
  - Supports third-party secret stores, such as Azure Key Vault, AWS Secret Manager, and Google Key Management, and Hashicorp Vault.

## Resources

- [Dapr Secrets Overview](https://docs.dapr.io/developing-applications/building-blocks/secrets/secrets-overview/)
- [Azure Key Vault Secret Store in Dapr](https://docs.dapr.io/reference/components-reference/supported-secret-stores/azure-keyvault/)
- [Secrets management quickstart](https://docs.dapr.io/getting-started/quickstarts/secrets-quickstart/): Retrieve secrets in the application code from a configured secret store using the secrets management API.
- [Secret Store tutorial](https://github.com/dapr/quickstarts/tree/master/tutorials/secretstore): Learn how to use the Dapr Secrets API to access secret stores.
- [Authenticating to Azure for Dapr](https://docs.dapr.io/developing-applications/integrations/azure/azure-authentication/authenticating-azure/)
- [How-to Guide for Managed Identities with Dapr](https://docs.dapr.io/developing-applications/integrations/azure/azure-authentication/howto-mi/)