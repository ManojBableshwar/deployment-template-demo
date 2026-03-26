#!/usr/bin/env bash
# Step 3 (REST API): Register model in the Azure ML registry
#
# Registry model registration via REST API is a 3-step process:
#   Step A: Create the model container (name-level entity)
#   Step B: Create the model version (metadata + triggers pending upload)
#   Step C: Start pending upload → get SAS URI → upload weights via azcopy
#
# Prerequisites: model weights already downloaded locally (run CLI step 3 first
# or use `huggingface-cli download`). azcopy must be installed.
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../env.sh"

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; exit 1; }

TOKEN=$(az account get-access-token --query accessToken -o tsv)

TEMPLATE_ASSET_ID="azureml://registries/${AZUREML_REGISTRY}/deploymentTemplates/${TEMPLATE_NAME}/versions/${TEMPLATE_VERSION}"
MODEL_DIR="$ROOT_DIR/model-artifacts"

# Verify model artifacts exist
[[ -d "$MODEL_DIR" ]] || error "Model directory '$MODEL_DIR' not found. Download model first."

# ─── Step A: Create model container ──────────────────────────────────────────
info "Step A: Creating model container '$MODEL_NAME'…"

RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
  "${REGISTRY_BASE}/models/${MODEL_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "properties": {
      "description": "Qwen3.5-0.8B — multimodal language model from HuggingFace",
      "tags": {
        "source": "huggingface",
        "hf_model_id": "Qwen/Qwen3.5-0.8B"
      }
    }
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)
if [[ "$HTTP_CODE" =~ ^2 ]]; then
  info "Model container created (HTTP $HTTP_CODE)."
else
  echo "WARN: HTTP $HTTP_CODE (container may already exist)"
  echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
fi

# ─── Step B: Create model version ───────────────────────────────────────────
info "Step B: Creating model version '$MODEL_NAME' v$MODEL_VERSION…"

RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
  "${REGISTRY_BASE}/models/${MODEL_NAME}/versions/${MODEL_VERSION}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "properties": {
      "description": "Qwen3.5-0.8B — multimodal language model (0.8B params, 262K context)",
      "modelType": "CustomModel",
      "tags": {
        "source": "huggingface",
        "hf_model_id": "Qwen/Qwen3.5-0.8B",
        "parameters": "0.8B",
        "framework": "transformers"
      },
      "properties": {
        "defaultDeploymentTemplate": "'"$TEMPLATE_ASSET_ID"'"
      }
    }
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)
if [[ "$HTTP_CODE" =~ ^2 ]]; then
  info "Model version created (HTTP $HTTP_CODE)."
else
  echo "ERROR: HTTP $HTTP_CODE"
  echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
  exit 1
fi

# ─── Step C: Start pending upload & upload weights ─────────────────────────
info "Step C: Starting pending upload for model weights…"

UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "${REGISTRY_BASE}/models/${MODEL_NAME}/versions/${MODEL_VERSION}/startPendingUpload?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "pendingUploadType": "TemporaryBlobReference"
  }')

HTTP_CODE=$(echo "$UPLOAD_RESPONSE" | tail -1)
UPLOAD_BODY=$(echo "$UPLOAD_RESPONSE" | head -n -1)

if [[ ! "$HTTP_CODE" =~ ^2 ]]; then
  echo "ERROR: Failed to start pending upload (HTTP $HTTP_CODE)"
  echo "$UPLOAD_BODY" | python3 -m json.tool 2>/dev/null || echo "$UPLOAD_BODY"
  exit 1
fi

# Extract the SAS URI from the response
BLOB_URI=$(echo "$UPLOAD_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['blobReferenceForConsumption']['blobUri'])")
SAS_URI=$(echo "$UPLOAD_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['blobReferenceForConsumption']['credential']['sasUri'])")

info "Blob URI: $BLOB_URI"
info "Uploading model weights from $MODEL_DIR …"

# Upload using azcopy (recursive directory upload)
if command -v azcopy &>/dev/null; then
  azcopy copy "$MODEL_DIR/*" "$SAS_URI" --recursive
elif command -v az &>/dev/null; then
  # Fallback: use az storage blob upload-batch
  # Parse container and path from the blob URI
  info "azcopy not found, falling back to az storage blob upload-batch…"
  az storage copy -s "$MODEL_DIR/*" -d "$SAS_URI" --recursive --only-show-errors
else
  error "Neither azcopy nor az CLI found. Install azcopy to upload model weights."
fi

info "Model registration complete: $MODEL_NAME v$MODEL_VERSION"
