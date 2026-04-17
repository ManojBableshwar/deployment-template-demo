#!/usr/bin/env bash
# Step 3: Upload model via azcopy and register in the Azure ML registry
#
# Uses azcopy for the large file upload (chunked PutBlock, resilient to
# connection resets) then registers the model via REST API to preserve
# the defaultDeploymentTemplate field.
#

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../env.sh"

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()   { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"
_step_start "Step 3: Register model"

MODEL_DIR="$ROOT_DIR/model-artifacts"

# -- Check if model already exists --------------------------------------------
if az ml model show --name "$MODEL_NAME" --version "$MODEL_VERSION" \
     --registry-name "$AZUREML_REGISTRY" &>/dev/null; then
  info "Model '$MODEL_NAME' v$MODEL_VERSION already exists in registry  -- skipping upload."

  # Always re-patch the deployment template reference (version may have changed)
  info "Ensuring deployment template is set to $TEMPLATE_NAME v$TEMPLATE_VERSION..."
  PATCH_URL="https://${REGISTRY_LOCATION}.api.azureml.ms/modelregistry/v1.0/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/registries/${AZUREML_REGISTRY}/models/${MODEL_NAME}:${MODEL_VERSION}"
  PATCH_TOKEN=$(az account get-access-token --query accessToken -o tsv)
  curl --fail -sS -X PATCH \
    "$PATCH_URL" \
    -H "Authorization: Bearer $PATCH_TOKEN" \
    -H "Content-Type: application/json" \
    -d '[{"op":"add","path":"/defaultDeploymentTemplate","value":{"assetId":"azureml://registries/'"$AZUREML_REGISTRY"'/deploymentTemplates/'"$TEMPLATE_NAME"'/versions/'"$TEMPLATE_VERSION"'"}}]'
  echo  # newline after curl output
  info "Deployment template patched on model."

  info "Showing details:"
  MODEL_JSON=$(az ml model show --name "$MODEL_NAME" --version "$MODEL_VERSION" \
    --registry-name "$AZUREML_REGISTRY" -o json)
  echo "$MODEL_JSON"

  # List model artifacts in blob storage to confirm file/dir layout
  MODEL_PATH=$(echo "$MODEL_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('path',''))" 2>/dev/null || true)
  if [[ -n "$MODEL_PATH" ]]; then
    info "Listing model artifacts in blob storage..."
    BLOB_TOKEN=$(az account get-access-token --query accessToken -o tsv)
    BLOB_LIST_RESP=$(curl -sS -X POST \
      "${REGISTRY_BASE}/models/${MODEL_NAME}/versions/${MODEL_VERSION}/startPendingUpload?api-version=${API_VERSION_PREVIEW}" \
      -H "Authorization: Bearer $BLOB_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"pendingUploadType": "TemporaryBlobReference"}')
    BLOB_SAS=$(echo "$BLOB_LIST_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['blobReferenceForConsumption']['credential']['sasUri'])" 2>/dev/null || true)
    if [[ -n "$BLOB_SAS" ]]; then
      azcopy list "$BLOB_SAS" --machine-readable 2>/dev/null || azcopy list "$BLOB_SAS" 2>/dev/null || warn "azcopy list failed"
    else
      warn "Could not get SAS URI for artifact listing"
    fi
  fi

  _step_end
  exit 0
fi

# -- Ensure model artifacts exist locally -------------------------------------
if [[ -d "$MODEL_DIR" && -n "$(ls -A "$MODEL_DIR" 2>/dev/null)" ]]; then
  info "Model artifacts already exist in $MODEL_DIR  -- skipping download."
else
  info "Downloading '$HF_MODEL_ID' from HuggingFace to $MODEL_DIR ..."
  pip3 install -q --break-system-packages huggingface_hub
  python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('$HF_MODEL_ID', local_dir='$MODEL_DIR')
"
  info "Download complete."
fi

# -- NOTE: Why we don't use `az ml model create` -----------------------------
# The CLI's built-in upload uses single-threaded Python SDK blob uploads which
# fail with BrokenPipeError / timeout on large model files (>1 GB).  Instead
# we use azcopy (chunked PutBlock, parallel, resilient to connection resets)
# and then register via REST API.
#
#   az ml model create \
#     --file "$SCRIPT_DIR/yaml/model.yml" \
#     --registry-name "$AZUREML_REGISTRY" \
#     --set version="$MODEL_VERSION" \
#     --set path="$MODEL_DIR" \
#     --set description="Qwen3.5-0.8B with deployment template v${MODEL_VERSION}" \
#     --set default_deployment_template.asset_id="azureml://registries/${AZUREML_REGISTRY}/deploymentTemplates/${TEMPLATE_NAME}/versions/${TEMPLATE_VERSION}"

# -- Step A: Get a temporary blob storage URI for uploading -------------------
info "Requesting temporary blob storage URI from registry..."
ACCESS_TOKEN=$(az account get-access-token --query accessToken -o tsv)

# 1. Start a pending upload to get a blob reference
PENDING_UPLOAD=$(curl -sS -X POST \
  "${REGISTRY_BASE}/models/${MODEL_NAME}/versions/${MODEL_VERSION}/startPendingUpload?api-version=${API_VERSION_PREVIEW}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pendingUploadType": "TemporaryBlobReference"
  }')

SAS_URI=$(echo "$PENDING_UPLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin)['blobReferenceForConsumption']['credential']['sasUri'])" 2>/dev/null || true)
BLOB_URI=$(echo "$PENDING_UPLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin)['blobReferenceForConsumption']['blobUri'])" 2>/dev/null || true)
PENDING_UPLOAD_ID=$(echo "$PENDING_UPLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin)['pendingUploadId'])" 2>/dev/null || true)

if [[ -z "$SAS_URI" ]]; then
  err "Failed to get SAS URI. Response:"
  echo "$PENDING_UPLOAD" | python3 -m json.tool 2>/dev/null || echo "$PENDING_UPLOAD"
  exit 1
fi

info "Got SAS URI (container): ${SAS_URI:0:80}..."
info "Pending upload ID: $PENDING_UPLOAD_ID"

# -- Step B: Upload model artifacts via azcopy --------------------------------
info "Uploading model artifacts via azcopy (~1.77 GB)..."
UPLOAD_START=$(date +%s)

azcopy copy \
  "${MODEL_DIR}/*" \
  "${SAS_URI}" \
  --recursive \
  --put-md5 \
  --log-level WARNING \
  --output-level essential

UPLOAD_END=$(date +%s)
UPLOAD_ELAPSED=$(( UPLOAD_END - UPLOAD_START ))
info "azcopy upload completed in ${UPLOAD_ELAPSED}s"

# -- Step C: Register the model asset via REST API ----------------------------
info "Creating model asset '$MODEL_NAME' v$MODEL_VERSION in registry via REST..."

# Refresh token in case upload took a while
ACCESS_TOKEN=$(az account get-access-token --query accessToken -o tsv)

MODEL_BODY=$(cat <<EOF
{
  "properties": {
    "description": "Qwen3.5-0.8B with deployment template v${MODEL_VERSION}  -- azcopy upload",
    "modelType": "custom_model",
    "modelUri": "${BLOB_URI}",
    "properties": {
      "aotManifest": "True"
    },
    "tags": {
      "source": "huggingface",
      "hf_model_id": "${HF_MODEL_ID}",
      "parameters": "0.8B",
      "framework": "transformers",
      "architecture": "qwen3_5"
    }
  }
}
EOF
)

CREATE_RESP=$(curl -sS -X PUT \
  "${REGISTRY_BASE}/models/${MODEL_NAME}/versions/${MODEL_VERSION}?api-version=${API_VERSION_PREVIEW}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$MODEL_BODY")

# Check for errors
PROV_STATE=$(echo "$CREATE_RESP" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('properties',{}).get('provisioningState',''))" 2>/dev/null || true)

if [[ "$PROV_STATE" == "Succeeded" || "$PROV_STATE" == "Creating" ]]; then
  info "Model asset created (provisioningState: $PROV_STATE)"
else
  ERROR_CODE=$(echo "$CREATE_RESP" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('error',{}).get('code',''))" 2>/dev/null || true)
  if [[ -n "$ERROR_CODE" ]]; then
    err "Model creation failed:"
    echo "$CREATE_RESP" | python3 -m json.tool 2>/dev/null || echo "$CREATE_RESP"
    exit 1
  fi
  warn "Unexpected provisioningState: '$PROV_STATE'  -- continuing"
  echo "$CREATE_RESP" | python3 -m json.tool 2>/dev/null || echo "$CREATE_RESP"
fi

# -- Patch: associate deployment template --------------------------------------
info "Associating deployment template with model via PATCH..."
PATCH_URL="https://${REGISTRY_LOCATION}.api.azureml.ms/modelregistry/v1.0/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/registries/${AZUREML_REGISTRY}/models/${MODEL_NAME}:${MODEL_VERSION}"
PATCH_TOKEN=$(az account get-access-token --query accessToken -o tsv)
curl --fail -sS -X PATCH \
  "$PATCH_URL" \
  -H "Authorization: Bearer $PATCH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{"op":"add","path":"/defaultDeploymentTemplate","value":{"assetId":"azureml://registries/'"$AZUREML_REGISTRY"'/deploymentTemplates/'"$TEMPLATE_NAME"'/versions/'"$TEMPLATE_VERSION"'"}}]'
echo  # newline after curl output
info "Deployment template patched on model."

# -- Verify -------------------------------------------------------------------
info "Verifying model in registry..."
MODEL_JSON=$(az ml model show \
  --name "$MODEL_NAME" \
  --version "$MODEL_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -o json)
echo "$MODEL_JSON"

# List model artifacts in blob storage to confirm file/dir layout
info "Listing model artifacts in blob storage..."
azcopy list "$SAS_URI" --machine-readable 2>/dev/null || azcopy list "$SAS_URI" 2>/dev/null || warn "azcopy list failed"

_step_end