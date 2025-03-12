#!/bin/bash

# Variables
source ../00-variables.sh
source ./00-variables.sh

# Check if the namespace exists in the cluster
RESULT=$(kubectl get namespace -o 'jsonpath={.items[?(@.metadata.name=="'$NAMESPACE'")].metadata.name'})

if [[ -n $RESULT ]]; then
  echo "[$NAMESPACE] namespace already exists in the cluster"
else
  echo "[$NAMESPACE] namespace does not exist in the cluster"
  echo "Creating [$NAMESPACE] namespace in the cluster..."
  kubectl create namespace $NAMESPACE
fi

# Create deployment
echo "Creating [$APP_NAME] deployment in the [$NAMESPACE] namespace..."
cat <<EOF | kubectl apply -n $NAMESPACE -f -
kind: Deployment
apiVersion: apps/v1
metadata:
  name: $APP_NAME
  labels:
    app: $APP_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP_NAME
      azure.workload.identity/use: "true"
  template:
    metadata:
      labels:
        app: $APP_NAME
        azure.workload.identity/use: "true"
      annotations:
        dapr.io/enabled: "true"
        dapr.io/app-id: "$APP_NAME"
        dapr.io/app-port: "80"
    spec:
      serviceAccountName: $SERVICE_ACCOUNT_NAME
      containers:
      - name: nginx
        image: nginx
        imagePullPolicy: Always
        ports:
          - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
EOF
