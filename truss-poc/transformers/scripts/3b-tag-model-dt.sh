#!/usr/bin/env bash
# ==============================================================================
# 3b-tag-model-dt.sh -- Tag the model with its default deployment template
#
# Uses the MFE (Model Registry) data-plane API to set the model's
# defaultDeploymentTemplate. Once tagged, deployments that reference this model
# inherit the DT's parameters (environment, env_vars, probes, request_settings,
# scoring_port) — so the deployment YAML does NOT need to duplicate them.
#
# Reference: existing repo pattern in
#   azureml-deployment-templates/scripts/cli/3-register-model.sh
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 3b: Tag model with deployment template ==="

az account set --subscription "$SUBSCRIPTION_ID"

# MFE model registry URL (data-plane)
MFE_MODEL_URL="https://${REGISTRY_LOCATION}.api.azureml.ms/modelregistry/v1.0/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/registries/${AZUREML_REGISTRY}/models/${TRUSS_MODEL_NAME}:${TRUSS_MODEL_VERSION}"

DT_REF="azureml://registries/${AZUREML_REGISTRY}/deploymentTemplates/${TRUSS_TEMPLATE_NAME}/versions/${TRUSS_TEMPLATE_VERSION}"

info "Model:  ${TRUSS_MODEL_NAME}:${TRUSS_MODEL_VERSION}"
info "DT ref: ${DT_REF}"

TOKEN=$(az account get-access-token --query accessToken -o tsv)

# 1. Patch defaultDeploymentTemplate (remove+add workaround for the change-existing bug)
info "Patching defaultDeploymentTemplate..."
curl -sS -o /dev/null -X PATCH "$MFE_MODEL_URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{"op":"remove","path":"/defaultDeploymentTemplate"}]' 2>/dev/null || true

RESP=$(curl -sS -w "\n%{http_code}" -X PATCH "$MFE_MODEL_URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{"op":"add","path":"/defaultDeploymentTemplate","value":{"assetId":"'"$DT_REF"'"}}]' 2>/dev/null)
HTTP_CODE=$(echo "$RESP" | tail -1)

if [[ "$HTTP_CODE" == "202" || "$HTTP_CODE" == "200" ]]; then
  ok "defaultDeploymentTemplate patched (HTTP $HTTP_CODE)"
else
  err "PATCH returned HTTP $HTTP_CODE"
  echo "$RESP" | head -n -1 | tee "$LOG_DIR/3b-tag-model-dt.log"
  exit 1
fi

# 2. Also set allowedDeploymentTemplates (label-based ref, required by MFE)
info "Patching allowedDeploymentTemplates..."
ALLOWED_JSON='[{"assetId":"azureml://registries/'"${AZUREML_REGISTRY}"'/deploymentTemplates/'"${TRUSS_TEMPLATE_NAME}"'/labels/latest"}]'
curl -sS -o /dev/null -X PATCH "$MFE_MODEL_URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{"op":"add","path":"/allowedDeploymentTemplates","value":'"$ALLOWED_JSON"'}]' 2>/dev/null || true

# 3. Verify
info "Verifying model DT association..."
az ml model show \
  --name "$TRUSS_MODEL_NAME" --version "$TRUSS_MODEL_VERSION" \
  --registry-name "$AZUREML_REGISTRY" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('  default_deployment_template:', d.get('default_deployment_template'))" \
  | tee "$LOG_DIR/3b-tag-model-dt.log"

ok "Model tagged with deployment template."
