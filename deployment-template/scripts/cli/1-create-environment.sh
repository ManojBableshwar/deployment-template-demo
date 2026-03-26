#!/usr/bin/env bash
# Step 1: Create vLLM environment in the Azure ML workspace (with Dockerfile build)
# Also creates in registry for deployment template reference.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"

# Create in workspace (Dockerfile build — needed for deployment)
if az ml environment show --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
     --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" -o none 2>/dev/null; then
  info "Environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION already exists in workspace — skipping."
else
  info "Creating environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION in workspace '$AZUREML_WORKSPACE'…"
  az ml environment create \
    --file "$SCRIPT_DIR/yaml/environment.yml" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP"
  info "Environment created in workspace."
fi

# Also create in registry (for deployment template) — non-critical, skip if hangs
if az ml environment show --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
     --registry-name "$AZUREML_REGISTRY" -o none 2>/dev/null; then
  info "Environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION already exists in registry — skipping."
else
  info "Creating environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION in registry (60s timeout)…"
  if timeout 60 az ml environment create \
    --file "$SCRIPT_DIR/yaml/environment.yml" \
    --registry-name "$AZUREML_REGISTRY" 2>&1; then
    info "Environment created in registry."
  else
    info "WARNING: Registry environment creation timed out or failed (non-critical)."
  fi
fi

info "Showing workspace environment:"
az ml environment show \
  --name "$ENVIRONMENT_NAME" \
  --version "$ENVIRONMENT_VERSION" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  -o json
