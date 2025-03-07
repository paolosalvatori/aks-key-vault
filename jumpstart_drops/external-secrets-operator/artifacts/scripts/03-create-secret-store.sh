#/bin/bash

# For more information, see:
# https://medium.com/@rcdinesh1/access-secrets-via-argocd-through-external-secrets-9173001be885
# https://external-secrets.io/latest/provider/azure-key-vault/

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Get key vault URL
VAULT_URL=$(az keyvault show \
  --name $KEY_VAULT_NAME \
  --resource-group $KEY_VAULT_RESOURCE_GROUP_NAME \
  --query properties.vaultUri \
  --output tsv \
  --only-show-errors)

if [[ -z $VAULT_URL ]]; then
  echo "[$KEY_VAULT_NAME] key vault URL not found"
  exit
fi

# Create secret store
echo "Creating the [$SECRET_STORE_NAME] secret store..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: $SECRET_STORE_NAME
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      vaultUrl: "$VAULT_URL"
      serviceAccountRef:
        name: $SERVICE_ACCOUNT_NAME
EOF

# Get the secret store
kubectl get secretstore azure-store -n $NAMESPACE -o yaml
