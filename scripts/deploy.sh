#!/usr/bin/env bash
set -euo pipefail

# Config
ACR_NAME=protohackeracr
APP_NAME=protohacker
DEPLOYMENT_NAME=protohacker
NAMESPACE=default
MANIFEST_FILE=k8s/deployment.yaml   # 👈 point to your YAML

echo "🔑 Logging into Azure Container Registry..."
az acr login --name $ACR_NAME

ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer --output tsv)
TIMESTAMP=$(date +'%Y%m%d%H%M%S')
IMAGE_NAME=$ACR_LOGIN_SERVER/$APP_NAME:$TIMESTAMP

echo "🐳 Building image..."
docker buildx build -t $APP_NAME:latest .

echo "🏷️ Tagging image as $IMAGE_NAME"
docker tag $APP_NAME:latest $IMAGE_NAME

echo "📤 Pushing image to ACR..."
docker push $IMAGE_NAME

# 🔁 Apply the full manifest (Deployment + Service)
echo ".ApplyResources manifest to ensure Service and Deployment are up to date..."
kubectl apply -f $MANIFEST_FILE --namespace $NAMESPACE

# 🖼️ Now update just the image
echo "🚀 Updating AKS Deployment $DEPLOYMENT_NAME with new image..."
kubectl set image deployment/$DEPLOYMENT_NAME \
  $APP_NAME=$IMAGE_NAME \
  --namespace $NAMESPACE

echo "🔄 Waiting for rollout to complete..."
kubectl rollout status deployment/$DEPLOYMENT_NAME --namespace $NAMESPACE

echo "✅ Deployment completed with tag: $TIMESTAMP"
