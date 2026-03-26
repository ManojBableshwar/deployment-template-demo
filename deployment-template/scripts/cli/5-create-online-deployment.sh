#!/usr/bin/env bash
# Step 5: Create a managed online deployment under the endpoint
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"

# Check if deployment already exists
if az ml online-deployment show --name "$DEPLOYMENT_NAME" --endpoint-name "$ENDPOINT_NAME" --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" -o none 2>/dev/null; then
  info "Deployment '$DEPLOYMENT_NAME' already exists — skipping creation."
else
  info "Creating online deployment '$DEPLOYMENT_NAME' under endpoint '$ENDPOINT_NAME'…"
  az ml online-deployment create \
    --file "$SCRIPT_DIR/yaml/deployment.yml" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --all-traffic
  info "Deployment created."
fi

info "Showing details:"
az ml online-deployment show \
  --name "$DEPLOYMENT_NAME" \
  --endpoint-name "$ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  -o json
