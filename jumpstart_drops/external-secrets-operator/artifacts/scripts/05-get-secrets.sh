#/bin/bash

# For more information, see:
# https://medium.com/@rcdinesh1/access-secrets-via-argocd-through-external-secrets-9173001be885
# https://external-secrets.io/latest/provider/azure-key-vault/

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Print secret values from the Kubernetes secret
json=$(kubectl get secret $EXTERNAL_SECRET_NAME -n $NAMESPACE -o jsonpath='{.data}')

# Decode the base64 of each value in the returned json
echo $json | jq -r 'to_entries[] | .key + ": " + (.value | @base64d)'