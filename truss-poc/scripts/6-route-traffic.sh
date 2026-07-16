#!/usr/bin/env bash
# ==============================================================================
# 6-route-traffic.sh -- Route 100% traffic to the Truss deployment
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 6: Route Traffic ==="
info "Routing 100% traffic to $TRUSS_DEPLOYMENT_NAME"

az account set --subscription "$SUBSCRIPTION_ID"

log_cmd "6-route-traffic.log" \
  az ml online-endpoint update \
    --name "$TRUSS_ENDPOINT_NAME" \
    --traffic "$TRUSS_DEPLOYMENT_NAME=100" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP"

EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
  ok "Traffic routed: $TRUSS_DEPLOYMENT_NAME=100%"
  az ml online-endpoint show \
    --name "$TRUSS_ENDPOINT_NAME" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query "{name:name, state:provisioning_state, traffic:traffic, uri:scoring_uri}" \
    -o table
else
  err "Traffic routing failed (exit code: $EXIT_CODE)"
  exit $EXIT_CODE
fi
