#!/bin/bash

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Add the external secrets repository
helm repo add external-secrets https://charts.external-secrets.io

# Update local Helm chart repository cache
helm repo update

# Deploy external secrets via Helm
helm upgrade external-secrets external-secrets/external-secrets \
  --install \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
