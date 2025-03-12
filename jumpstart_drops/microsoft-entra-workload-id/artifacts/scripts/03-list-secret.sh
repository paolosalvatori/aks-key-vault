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

# Read logs from the pod
echo "Reading logs from [$POD_NAME] pod..."
kubectl logs $POD -n $NAMESPACE