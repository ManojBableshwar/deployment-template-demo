#!/usr/bin/env bash
# ==============================================================================
# 2b-register-model-manifest.sh -- Register model with an AOT manifest
#
# The DT-based deployment flow requires the model to have a "model feed"
# (modelManifestPathOrUri). A plain `az ml model create` from a local path does
# NOT produce this, causing "InvalidModelFeed" at deployment time.
#
# This script uses the registry data-plane flow that DOES produce the manifest:
#   1. startPendingUpload  -> temporary SAS URI + blob URI
#   2. azcopy copy         -> upload model artifacts to the SAS URI
#   3. PUT model asset      -> with properties.aotManifest = "True"
#
# Mirrors the working pattern in
#   azureml-deployment-templates/scripts/cli/3-register-model.sh
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 2b: Register model WITH AOT manifest ==="
info "Model:   ${TRUSS_MODEL_NAME}:${TRUSS_MODEL_VERSION}"
info "Weights: ${MODEL_ARTIFACTS_DIR}"

az account set --subscription "$SUBSCRIPTION_ID"

REGISTRY_BASE="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/registries/${AZUREML_REGISTRY}"
API_VERSION_PREVIEW="${API_VERSION_PREVIEW:-2025-04-01-preview}"

# -- Step A: start pending upload (get SAS + blob URI) -------------------------
info "Requesting temporary blob storage URI..."
TOKEN=$(az account get-access-token --query accessToken -o tsv)
PENDING_UPLOAD=$(curl -sS -X POST \
  "${REGISTRY_BASE}/models/${TRUSS_MODEL_NAME}/versions/${TRUSS_MODEL_VERSION}/startPendingUpload?api-version=${API_VERSION_PREVIEW}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"pendingUploadType": "TemporaryBlobReference"}')

SAS_URI=$(echo "$PENDING_UPLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin)['blobReferenceForConsumption']['credential']['sasUri'])" 2>/dev/null || true)
BLOB_URI=$(echo "$PENDING_UPLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin)['blobReferenceForConsumption']['blobUri'])" 2>/dev/null || true)

if [[ -z "$SAS_URI" || -z "$BLOB_URI" ]]; then
  err "Failed to get SAS URI. Response:"
  echo "$PENDING_UPLOAD" | python3 -m json.tool 2>/dev/null || echo "$PENDING_UPLOAD"
  exit 1
fi
info "SAS URI (container): ${SAS_URI:0:80}..."

# -- Step B: upload weights via azcopy ----------------------------------------
info "Uploading model artifacts via azcopy (this may take a few minutes)..."
azcopy copy "${MODEL_ARTIFACTS_DIR}/*" "${SAS_URI}" \
  --recursive --put-md5 --log-level WARNING --output-level essential \
  2>&1 | tee "$LOG_DIR/2b-azcopy.log"

# -- Step C: register model asset with aotManifest ----------------------------
info "Registering model asset with aotManifest=True..."
TOKEN=$(az account get-access-token --query accessToken -o tsv)
MODEL_BODY=$(cat <<EOF
{
  "properties": {
    "description": "Qwen/Qwen3.5-0.8B for Truss PoC (AOT manifest, azcopy upload)",
    "modelType": "custom_model",
    "modelUri": "${BLOB_URI}",
    "properties": { "aotManifest": "True" },
    "tags": { "framework": "truss", "hf_model_id": "Qwen/Qwen3.5-0.8B", "packaging": "mounted-weights" }
  }
}
EOF
)
CREATE_RESP=$(curl -sS -X PUT \
  "${REGISTRY_BASE}/models/${TRUSS_MODEL_NAME}/versions/${TRUSS_MODEL_VERSION}?api-version=${API_VERSION_PREVIEW}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$MODEL_BODY")

PROV_STATE=$(echo "$CREATE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('provisioningState',''))" 2>/dev/null || true)
if [[ "$PROV_STATE" == "Succeeded" || "$PROV_STATE" == "Creating" ]]; then
  ok "Model asset created (provisioningState: $PROV_STATE)"
else
  err "Model creation failed:"
  echo "$CREATE_RESP" | python3 -m json.tool 2>/dev/null | tee "$LOG_DIR/2b-register-model-manifest.log"
  exit 1
fi

# -- Verify manifest ----------------------------------------------------------
info "Verifying model has a manifest (model feed)..."
az ml model show --name "$TRUSS_MODEL_NAME" --version "$TRUSS_MODEL_VERSION" \
  --registry-name "$AZUREML_REGISTRY" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('  properties:', d.get('properties'))" \
  | tee "$LOG_DIR/2b-register-model-manifest.log"

ok "Model registered with AOT manifest."
