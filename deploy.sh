#!/bin/bash

set -euo pipefail

# --- Usage ---
if [ $# -lt 1 ]; then
  echo "Usage: ./deploy.sh <config.yaml>"
  echo ""
  echo "  Deploys Uji to Cloud Run using values from a YAML config file."
  echo "  See deploy_config.example.yaml for the expected format."
  exit 1
fi

CONFIG_FILE="$1"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Config file not found: $CONFIG_FILE"
  exit 1
fi

# --- Check for yq ---
if ! command -v yq &>/dev/null; then
  echo "ERROR: yq is required but not installed."
  echo "Install it with: brew install yq"
  exit 1
fi

# --- Read config ---
SERVICE_NAME=$(yq '.service_name // ""' "$CONFIG_FILE")
BUCKET_NAME=$(yq '.bucket_name // ""' "$CONFIG_FILE")
REGION=$(yq '.region // "us-central1"' "$CONFIG_FILE")
FORWARD_URL=$(yq '.forward_url // ""' "$CONFIG_FILE")
FORWARD_AUTH_TOKEN="${FORWARD_AUTH_TOKEN:-}"
DATABRICKS_WORKSPACE_URL=$(yq '.databricks_workspace_url // ""' "$CONFIG_FILE")
DATABRICKS_TABLE_NAME=$(yq '.databricks_table_name // ""' "$CONFIG_FILE")

# --- Validate required fields ---
if [ -z "$SERVICE_NAME" ]; then
  echo "ERROR: service_name is required in $CONFIG_FILE"
  exit 1
fi

if [ -z "$BUCKET_NAME" ]; then
  echo "ERROR: bucket_name is required in $CONFIG_FILE"
  exit 1
fi

# --- Warn on partial forwarding config ---
if [ -n "$FORWARD_URL" ] && [ -z "$FORWARD_AUTH_TOKEN" ]; then
  echo "WARNING: forward_url is set but FORWARD_AUTH_TOKEN env var is missing"
fi
if [ -z "$FORWARD_URL" ] && [ -n "$FORWARD_AUTH_TOKEN" ]; then
  echo "WARNING: FORWARD_AUTH_TOKEN env var is set but forward_url is missing in config"
fi

# --- Git / CI check ---
GIT_SHA=$(git rev-parse --short HEAD)
FULL_SHA=$(git rev-parse HEAD)
IMAGE_TAG=sha-$GIT_SHA

echo "Checking CI status for $GIT_SHA..."
WORKFLOW_STATUS=$(gh run list --workflow=docker-publish.yml --commit="$FULL_SHA" --json status,conclusion --jq '.[0].conclusion // .[0].status' 2>/dev/null)

if [ -z "$WORKFLOW_STATUS" ]; then
  echo "ERROR: No CI workflow run found for commit $GIT_SHA."
  echo "Has this commit been pushed? Run: git push"
  exit 1
elif [ "$WORKFLOW_STATUS" = "success" ]; then
  echo "CI passed — image simonmok/uji:$IMAGE_TAG is ready."
elif [ "$WORKFLOW_STATUS" = "in_progress" ] || [ "$WORKFLOW_STATUS" = "queued" ]; then
  echo "ERROR: CI workflow is still running for commit $GIT_SHA."
  echo "Wait for it to finish: gh run watch"
  exit 1
else
  echo "ERROR: CI workflow failed for commit $GIT_SHA (status: $WORKFLOW_STATUS)."
  echo "Check the run: gh run list --workflow=docker-publish.yml"
  exit 1
fi

# --- Deployment summary ---
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

# --- Create bucket if needed ---
if ! gsutil ls -b gs://$BUCKET_NAME &>/dev/null; then
  read -p "Bucket $BUCKET_NAME does not exist. Create it? [y/N]: " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Creating bucket $BUCKET_NAME..."
    gsutil mb gs://$BUCKET_NAME
  else
    echo "Aborting — bucket is required for deployment."
    exit 1
  fi
else
  echo "Bucket $BUCKET_NAME already exists."
fi

# --- Build env vars ---
ENV_VARS="GCS_BUCKET_NAME=$BUCKET_NAME,VECTOR_LOG=info"
[ -n "$FORWARD_URL" ] && ENV_VARS+=",FORWARD_URL=$FORWARD_URL"
[ -n "$FORWARD_AUTH_TOKEN" ] && ENV_VARS+=",FORWARD_AUTH_TOKEN=$FORWARD_AUTH_TOKEN"
[ -n "$DATABRICKS_WORKSPACE_URL" ] && ENV_VARS+=",DATABRICKS_WORKSPACE_URL=$DATABRICKS_WORKSPACE_URL"
[ -n "$DATABRICKS_TABLE_NAME" ] && ENV_VARS+=",DATABRICKS_TABLE_NAME=$DATABRICKS_TABLE_NAME"

# --- Deploy ---
echo "Deploying Cloud Run service $SERVICE_NAME..."
gcloud run deploy $SERVICE_NAME \
	--image simonmok/uji:$IMAGE_TAG \
	--allow-unauthenticated \
	--region $REGION \
	--set-env-vars "$ENV_VARS"
