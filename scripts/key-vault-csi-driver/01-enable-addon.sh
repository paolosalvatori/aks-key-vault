#!/bin/bash

# For more information, see:
# https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver
# https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-identity-access

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