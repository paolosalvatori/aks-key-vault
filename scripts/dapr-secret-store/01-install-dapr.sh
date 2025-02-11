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
