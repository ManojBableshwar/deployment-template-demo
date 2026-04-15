#!/usr/bin/env bash
# Step 4: Create a managed online endpoint in the Azure ML workspace
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"
_step_start "Step 4: Create online endpoint"

# Check if endpoint already exists
if az ml online-endpoint show --name "$ENDPOINT_NAME" --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" 2>&1; then
  info "Endpoint '$ENDPOINT_NAME' already exists — skipping creation."
else
  info "Creating online endpoint '$ENDPOINT_NAME' in workspace '$AZUREML_WORKSPACE'…"
  az ml online-endpoint create \
    --file "$SCRIPT_DIR/yaml/endpoint.yml" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP"
  info "Endpoint created."
fi

info "Showing details:"
az ml online-endpoint show \
  --name "$ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  -o json

_step_end
