#!/bin/bash

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Check if the pod exists
POD=$(kubectl get pod $POD_NAME -n $NAMESPACE -o 'jsonpath={.metadata.name}')

if [[ -z $POD ]]; then
    echo "No [$POD_NAME] pod found in [$NAMESPACE] namespace."
    exit
fi

# List secrets from /mnt/secrets volume
echo "Reading files from [/mnt/secrets] volume in [$POD_NAME] pod..."
FILES=$(kubectl exec $POD -n $NAMESPACE -- ls /mnt/secrets)

# Retrieve secrets from /mnt/secrets volume
for FILE in ${FILES[@]}
do
    echo "Retrieving [$FILE] secret from [$KEY_VAULT_NAME] key vault..."
    kubectl exec $POD --stdin --tty -n $NAMESPACE -- cat /mnt/secrets/$FILE;echo;sleep 1
done 