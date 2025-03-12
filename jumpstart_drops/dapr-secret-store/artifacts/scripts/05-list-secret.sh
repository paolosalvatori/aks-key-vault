#!/bin/bash

# References
# https://docs.dapr.io/developing-applications/building-blocks/secrets/secrets-overview/

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