#!/usr/bin/env bash
# Step 1: Create vLLM environment in the Azure ML workspace (with Dockerfile build)
# Also creates in registry for deployment template reference.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"

# Create in workspace (Dockerfile build — needed for deployment)
if az ml environment show --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
     --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" -o none 2>/dev/null; then
  info "Environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION already exists in workspace — proceeding."
else
  info "Creating environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION in workspace '$AZUREML_WORKSPACE'…"
  az ml environment create \
    --file "$SCRIPT_DIR/yaml/environment.yml" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP"
  info "Environment create command completed."
fi

# Promote environment to registry (by sharing from workspace)
if az ml environment show --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
     --registry-name "$AZUREML_REGISTRY" -o none 2>/dev/null; then
  info "Environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION already exists in registry — skipping promotion."
else
  info "Promoting environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION from workspace to registry…"
  az ml environment share \
    --name "$ENVIRONMENT_NAME" \
    --version "$ENVIRONMENT_VERSION" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --share-with-name "$ENVIRONMENT_NAME" \
    --share-with-version "$ENVIRONMENT_VERSION" \
    --registry-name "$AZUREML_REGISTRY" 2>&1
  info "Environment share command completed — verifying it landed in registry…"

  # Verify the environment actually exists in registry after share
  if az ml environment show --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
       --registry-name "$AZUREML_REGISTRY" -o none 2>/dev/null; then
    info "Confirmed: environment exists in registry."
  else
    error "Environment share succeeded but environment not found in registry!"
    exit 1
  fi
fi

info "Showing registry environment:"
az ml environment show \
  --name "$ENVIRONMENT_NAME" \
  --version "$ENVIRONMENT_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -o json
