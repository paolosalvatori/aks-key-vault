#/bin/bash

# For more information, see:
# https://medium.com/@rcdinesh1/access-secrets-via-argocd-through-external-secrets-9173001be885
# https://external-secrets.io/latest/provider/azure-key-vault/

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Create secrets
cat <<EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: $EXTERNAL_SECRET_NAME
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: SecretStore
    name:  $SECRET_STORE_NAME
  target:
    name: $EXTERNAL_SECRET_NAME
    creationPolicy: Owner
  dataFrom:
  # find all secrets starting with user
  - find:
      name:
        regexp: "^user"
  data:
  # explicit type and name of secret in the Azure KV
  - secretKey: password
    remoteRef:
      key: secret/password
EOF
