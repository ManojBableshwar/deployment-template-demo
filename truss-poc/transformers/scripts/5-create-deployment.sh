#!/usr/bin/env bash
# ==============================================================================
# 5-create-deployment.sh -- Create managed online deployment from DT
#
# This creates the deployment using the deployment YAML that was generated
# from the deployment template. The mapping is documented in yaml/deployment.yml.
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 5: Create Online Deployment ==="
info "Deployment: $TRUSS_DEPLOYMENT_NAME → Endpoint: $TRUSS_ENDPOINT_NAME"

az account set --subscription "$SUBSCRIPTION_ID"

# -- Check if deployment already exists ----------------------------------------
if az ml online-deployment show \
    --name "$TRUSS_DEPLOYMENT_NAME" \
    --endpoint-name "$TRUSS_ENDPOINT_NAME" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    -o none 2>/dev/null; then
  PROV_STATE=$(az ml online-deployment show \
    --name "$TRUSS_DEPLOYMENT_NAME" \
    --endpoint-name "$TRUSS_ENDPOINT_NAME" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query "provisioning_state" -o tsv)
  if [[ "$PROV_STATE" == "Succeeded" ]]; then
    ok "Deployment already exists and succeeded: $TRUSS_DEPLOYMENT_NAME"
    exit 0
  else
    warn "Deployment exists but state=$PROV_STATE. Deleting and recreating..."
    az ml online-endpoint update \
      --name "$TRUSS_ENDPOINT_NAME" \
      --traffic "$TRUSS_DEPLOYMENT_NAME=0" \
      --workspace-name "$AZUREML_WORKSPACE" \
      --resource-group "$RESOURCE_GROUP" \
      -o none 2>/dev/null || true
    az ml online-deployment delete \
      --name "$TRUSS_DEPLOYMENT_NAME" \
      --endpoint-name "$TRUSS_ENDPOINT_NAME" \
      --workspace-name "$AZUREML_WORKSPACE" \
      --resource-group "$RESOURCE_GROUP" \
      --yes -o none 2>/dev/null || true
  fi
fi

# -- Create deployment ---------------------------------------------------------
info "Creating deployment (this may take 15-30 minutes for GPU provisioning)..."

log_cmd "5-create-deployment.log" \
  az ml online-deployment create \
    --file "$YAML_DIR/deployment.yml" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --all-traffic

EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
  ok "Deployment created: $TRUSS_DEPLOYMENT_NAME"
else
  err "Deployment creation failed (exit code: $EXIT_CODE)"
  err "Check logs: $LOG_DIR/5-create-deployment.log"
  info "Fetching startup logs..."
  az ml online-deployment get-logs \
    --name "$TRUSS_DEPLOYMENT_NAME" \
    --endpoint-name "$TRUSS_ENDPOINT_NAME" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --lines 100 2>&1 | tee "$LOG_DIR/5-startup-logs.log" || true
  exit $EXIT_CODE
fi
