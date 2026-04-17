#!/usr/bin/env bash
# Step 2: Create deployment template in the Azure ML registry
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"
_step_start "Step 2: Create deployment template"

# Check if deployment template already exists
if az ml deployment-template show --name "$TEMPLATE_NAME" --version "$TEMPLATE_VERSION" --registry-name "$AZUREML_REGISTRY" 2>&1; then
  info "Deployment template '$TEMPLATE_NAME' v$TEMPLATE_VERSION already exists -- skipping creation."
else
  info "Creating deployment template '$TEMPLATE_NAME' v$TEMPLATE_VERSION in registry '$AZUREML_REGISTRY'..."
  az ml deployment-template create \
    --file "$SCRIPT_DIR/yaml/deployment-template.yml" \
    --registry-name "$AZUREML_REGISTRY"
  info "Deployment template created."
fi

info "Showing details:"
az ml deployment-template show \
  --name "$TEMPLATE_NAME" \
  --version "$TEMPLATE_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -o json

_step_end
