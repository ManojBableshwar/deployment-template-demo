#!/usr/bin/env bash
# ==============================================================================
# 4-create-endpoint.sh -- Create managed online endpoint
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 4: Create Online Endpoint ==="
info "Endpoint: $TRUSS_ENDPOINT_NAME"

az account set --subscription "$SUBSCRIPTION_ID"

# -- Check if endpoint already exists ------------------------------------------
if az ml online-endpoint show \
    --name "$TRUSS_ENDPOINT_NAME" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    -o none 2>/dev/null; then
  ok "Endpoint already exists: $TRUSS_ENDPOINT_NAME"
  exit 0
fi

# -- Create endpoint -----------------------------------------------------------
info "Creating endpoint..."

log_cmd "4-create-endpoint.log" \
  az ml online-endpoint create \
    --file "$YAML_DIR/endpoint.yml" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP"

EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
  ok "Endpoint created: $TRUSS_ENDPOINT_NAME"
  # Show endpoint details
  az ml online-endpoint show \
    --name "$TRUSS_ENDPOINT_NAME" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query "{name:name, state:provisioning_state, uri:scoring_uri}" \
    -o table
else
  err "Endpoint creation failed (exit code: $EXIT_CODE)"
  err "Check logs: $LOG_DIR/4-create-endpoint.log"
  exit $EXIT_CODE
fi
