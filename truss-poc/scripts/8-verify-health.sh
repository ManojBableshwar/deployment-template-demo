#!/usr/bin/env bash
# ==============================================================================
# 8-verify-health.sh -- Verify health probes, fetch logs, confirm behavior
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 8: Verify Health & Logs ==="

az account set --subscription "$SUBSCRIPTION_ID"

# -- Deployment status ---------------------------------------------------------
info "Deployment status:"
az ml online-deployment show \
  --name "$TRUSS_DEPLOYMENT_NAME" \
  --endpoint-name "$TRUSS_ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  --query "{name:name, state:provisioning_state, instance_type:instance_type, model:model}" \
  -o table | tee "$LOG_DIR/8-deployment-status.log"

# -- Fetch startup logs --------------------------------------------------------
info "Fetching deployment logs (last 200 lines)..."
az ml online-deployment get-logs \
  --name "$TRUSS_DEPLOYMENT_NAME" \
  --endpoint-name "$TRUSS_ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  --lines 200 2>&1 | tee "$LOG_DIR/8-deployment-logs.log"

# -- Endpoint metrics ----------------------------------------------------------
info "Endpoint details:"
az ml online-endpoint show \
  --name "$TRUSS_ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  --query "{name:name, state:provisioning_state, traffic:traffic, scoring_uri:scoring_uri, auth_mode:auth_mode}" \
  -o table | tee -a "$LOG_DIR/8-endpoint-details.log"

# -- Probe verification --------------------------------------------------------
info "Probe verification (via scoring URI)..."
SCORING_URI=$(az ml online-endpoint show \
  --name "$TRUSS_ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  --query "scoring_uri" -o tsv)
SCORING_KEY=$(az ml online-endpoint get-credentials \
  --name "$TRUSS_ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  --query "primaryKey" -o tsv)
BASE_URI="${SCORING_URI%/}"

echo "" | tee -a "$LOG_DIR/8-probe-verification.log"
echo "--- Liveness (GET /) ---" | tee -a "$LOG_DIR/8-probe-verification.log"
curl -s -w "\nHTTP Status: %{http_code}\nTime: %{time_total}s\n" \
  -H "Authorization: Bearer $SCORING_KEY" \
  "$BASE_URI/" | tee -a "$LOG_DIR/8-probe-verification.log"

echo "" | tee -a "$LOG_DIR/8-probe-verification.log"
echo "--- Readiness (GET /v1/models/model) ---" | tee -a "$LOG_DIR/8-probe-verification.log"
curl -s -w "\nHTTP Status: %{http_code}\nTime: %{time_total}s\n" \
  -H "Authorization: Bearer $SCORING_KEY" \
  "$BASE_URI/v1/models/model" | tee -a "$LOG_DIR/8-probe-verification.log"

echo ""
ok "Health verification complete. Logs at: $LOG_DIR/"
