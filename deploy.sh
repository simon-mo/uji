#!/bin/bash

prompt_var() {
  local var_name=$1 prompt_text=$2 default=$3
  local current_val="${!var_name}"
  if [ -z "$current_val" ]; then
    read -p "$prompt_text [$default]: " input
    eval "$var_name=\${input:-$default}"
  fi
}

# --- Service ---
prompt_var SERVICE_NAME "Service name" "uji"

# --- Storage ---
prompt_var BUCKET_NAME "GCS bucket name" ""

# --- HTTP Forwarding (optional) ---
prompt_var FORWARD_URL "Forward URL" ""
prompt_var FORWARD_AUTH_TOKEN "Bearer token for forwarding" ""
prompt_var DATABRICKS_WORKSPACE_URL "Databricks workspace URL" ""
prompt_var DATABRICKS_TABLE_NAME "Databricks table (catalog.schema.table)" ""

REGION="us-central1"
GIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG=sha-$GIT_SHA

# Show all variables and wait for confirmation
echo ""
echo "=== Deployment Summary ==="
echo "SERVICE_NAME: $SERVICE_NAME"
echo "BUCKET_NAME: $BUCKET_NAME"
echo "REGION: $REGION"
echo "IMAGE_TAG: $IMAGE_TAG"
[ -n "$FORWARD_URL" ] && echo "FORWARD_URL: $FORWARD_URL"
[ -n "$FORWARD_AUTH_TOKEN" ] && echo "FORWARD_AUTH_TOKEN: (set)"
[ -n "$DATABRICKS_WORKSPACE_URL" ] && echo "DATABRICKS_WORKSPACE_URL: $DATABRICKS_WORKSPACE_URL"
[ -n "$DATABRICKS_TABLE_NAME" ] && echo "DATABRICKS_TABLE_NAME: $DATABRICKS_TABLE_NAME"
echo "=========================="
read -p "Do you want to continue? " -n 1 -r
echo

# Create Cloud Storage bucket if it doesn't exist
if ! gsutil ls -b gs://$BUCKET_NAME &>/dev/null; then
  echo "Creating bucket $BUCKET_NAME..."
  gsutil mb gs://$BUCKET_NAME
else
  echo "Bucket $BUCKET_NAME already exists."
fi

# Build env vars string dynamically
ENV_VARS="GCS_BUCKET_NAME=$BUCKET_NAME,VECTOR_LOG=info"
[ -n "$FORWARD_URL" ] && ENV_VARS+=",FORWARD_URL=$FORWARD_URL"
[ -n "$FORWARD_AUTH_TOKEN" ] && ENV_VARS+=",FORWARD_AUTH_TOKEN=$FORWARD_AUTH_TOKEN"
[ -n "$DATABRICKS_WORKSPACE_URL" ] && ENV_VARS+=",DATABRICKS_WORKSPACE_URL=$DATABRICKS_WORKSPACE_URL"
[ -n "$DATABRICKS_TABLE_NAME" ] && ENV_VARS+=",DATABRICKS_TABLE_NAME=$DATABRICKS_TABLE_NAME"

# Deploy Cloud Run service
echo "Deploying Cloud Run service $SERVICE_NAME..."
gcloud run deploy $SERVICE_NAME \
	--image simonmok/uji:$IMAGE_TAG \
	--allow-unauthenticated \
	--region $REGION \
	--set-env-vars "$ENV_VARS"
