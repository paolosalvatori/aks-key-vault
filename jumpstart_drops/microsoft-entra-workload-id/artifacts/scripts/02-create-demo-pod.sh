#/bin/bash

# For more information, see: https://github.com/Azure/azure-workload-identity/blob/main/examples/msal-net/akvdotnet/Program.cs

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Retrieve the Azure Key Vault URL
echo "Retrieving the [$KEY_VAULT_NAME] key vault URL..."
KEYVAULT_URL=$(az keyvault show \
  --name $KEY_VAULT_NAME \
  --query properties.vaultUri \
  --output tsv)

if [[ -n $KEYVAULT_URL ]]; then
  echo "[$KEYVAULT_URL] key vault URL successfully retrieved"
else
  echo "Failed to retrieve the [$KEY_VAULT_NAME] key vault URL"
  exit
fi

# Create the pod
echo "Creating the [$POD_NAME] pod in the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD_NAME
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: $SERVICE_ACCOUNT_NAME
  containers:
    - image: ghcr.io/azure/azure-workload-identity/msal-net:latest
      name: oidc
      env:
      - name: KEYVAULT_URL
        value: $KEYVAULT_URL
      - name: SECRET_NAME
        value: ${SECRETS[0]}
  nodeSelector:
    kubernetes.io/os: linux
EOF
exit
