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