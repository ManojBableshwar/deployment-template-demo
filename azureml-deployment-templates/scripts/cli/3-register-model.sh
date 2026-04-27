#!/usr/bin/env bash
# Step 3: Upload model via azcopy and register in the Azure ML registry
# Uses MFE data-plane APIs for:
#   - defaultDeploymentTemplate  (TP=1 DT, version-based ref)
#   - allowedDeploymentTemplates (all TP DTs, label-based refs)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()   { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"
_step_start "Step 3: Register model"

# -- Read TP list from environment --------------------------------------------
read -ra TPS <<< "${E2E_TPS:-1}"

# MFE model registry URL (data-plane)
MFE_MODEL_URL="https://${REGISTRY_LOCATION}.api.azureml.ms/modelregistry/v1.0/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/registries/${AZUREML_REGISTRY}/models/${MODEL_NAME}:${MODEL_VERSION}"

# The default DT is always TP=1 (or the first TP in the list)
DEFAULT_TP="${TPS[0]}"
DEFAULT_DT_NAME=$(tp_template_name "$DEFAULT_TP")
DEFAULT_DT_REF="azureml://registries/${AZUREML_REGISTRY}/deploymentTemplates/${DEFAULT_DT_NAME}/versions/${TEMPLATE_VERSION}"

# Build the allowed DTs list (label-based refs, required by MFE)
ALLOWED_DTS_JSON="["
for i in "${!TPS[@]}"; do
  local_tp="${TPS[$i]}"
  local_dt_name=$(tp_template_name "$local_tp")
  if (( i > 0 )); then ALLOWED_DTS_JSON+=","; fi
  ALLOWED_DTS_JSON+="{\"assetId\":\"azureml://registries/${AZUREML_REGISTRY}/deploymentTemplates/${local_dt_name}/labels/latest\"}"
done
ALLOWED_DTS_JSON+="]"

info "Default DT (TP=${DEFAULT_TP}): $DEFAULT_DT_REF"
info "Allowed DTs: $ALLOWED_DTS_JSON"

# -- Helper: patch DTs on an existing model -----------------------------------
patch_model_dts() {
  local token
  token=$(az account get-access-token --query accessToken -o tsv)

  # 1. Patch defaultDeploymentTemplate (remove+add workaround for the change-existing bug)
  info "Patching defaultDeploymentTemplate → $DEFAULT_DT_REF"
  # Remove first (idempotent — 202 if exists, 4xx if not → ignore)
  curl -sS -o /dev/null -w "" -X PATCH "$MFE_MODEL_URL" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d '[{"op":"remove","path":"/defaultDeploymentTemplate"}]' 2>/dev/null || true

  local resp http_code
  resp=$(curl -sS -w "\n%{http_code}" -X PATCH "$MFE_MODEL_URL" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d '[{"op":"add","path":"/defaultDeploymentTemplate","value":{"assetId":"'"$DEFAULT_DT_REF"'"}}]' 2>/dev/null)
  http_code=$(echo "$resp" | tail -1)
  if [[ "$http_code" == "202" || "$http_code" == "200" ]]; then
    info "defaultDeploymentTemplate patched (HTTP $http_code)."
  else
    warn "defaultDeploymentTemplate PATCH returned HTTP $http_code (may not resolve Dockerfile-based env in DT)."
    warn "Response: $(echo "$resp" | head -n -1 | head -3)"
    warn "This is non-blocking (discoverability only). Proceeding."
  fi

  # 2. Patch allowedDeploymentTemplates (label-based refs)
  info "Patching allowedDeploymentTemplates with ${#TPS[@]} DT(s)..."
  resp=$(curl -sS -w "\n%{http_code}" -X PATCH "$MFE_MODEL_URL" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d '[{"op":"add","path":"/allowedDeploymentTemplates","value":'"$ALLOWED_DTS_JSON"'}]' 2>/dev/null)
  http_code=$(echo "$resp" | tail -1)
  if [[ "$http_code" == "202" || "$http_code" == "200" ]]; then
    info "allowedDeploymentTemplates patched (HTTP $http_code)."
  else
    warn "allowedDeploymentTemplates PATCH returned HTTP $http_code."
    warn "Response: $(echo "$resp" | head -n -1 | head -3)"
    warn "This is non-blocking. Proceeding."
  fi
}

# -- Helper: verify DTs on the model via MFE GET ------------------------------
verify_model_dts() {
  local token
  token=$(az account get-access-token --query accessToken -o tsv)
  local model_json
  model_json=$(curl -sS "$MFE_MODEL_URL" \
    -H "Authorization: Bearer $token" 2>/dev/null)

  local current_default current_allowed
  current_default=$(echo "$model_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('defaultDeploymentTemplate',{}).get('assetId',''))" 2>/dev/null || true)
  current_allowed=$(echo "$model_json" | python3 -c "
import sys,json
d=json.load(sys.stdin)
allowed = d.get('allowedDeploymentTemplates',[])
for a in allowed:
    print(a.get('assetId',''))
" 2>/dev/null || true)

  info "Verified model DTs:"
  info "  defaultDeploymentTemplate: ${current_default:-<none>}"
  if [[ -n "$current_allowed" ]]; then
    while IFS= read -r adt; do
      [[ -n "$adt" ]] && info "  allowedDeploymentTemplate: $adt"
    done <<< "$current_allowed"
  else
    info "  allowedDeploymentTemplates: <none>"
  fi
}

# -- Check if model already exists --------------------------------------------
if az ml model show --name "$MODEL_NAME" --version "$MODEL_VERSION" \
     --registry-name "$AZUREML_REGISTRY" &>/dev/null; then
  info "Model '$MODEL_NAME' v$MODEL_VERSION already exists in registry -- skipping upload."

  # Always re-patch DTs (versions/labels may have changed)
  patch_model_dts
  verify_model_dts

  info "Showing model details:"
  az ml model show --name "$MODEL_NAME" --version "$MODEL_VERSION" \
    --registry-name "$AZUREML_REGISTRY" -o json 2>/dev/null

  _step_end
  exit 0
fi

# -- Verify model artifacts exist locally (downloaded in step 0) --------------
if [[ ! -d "$MODEL_DIR" ]] || ! compgen -G "$MODEL_DIR"/*.safetensors >/dev/null 2>&1 \
    && ! compgen -G "$MODEL_DIR"/*.bin >/dev/null 2>&1 \
    && ! compgen -G "$MODEL_DIR"/*.gguf >/dev/null 2>&1; then
  err "No model weight files found in $MODEL_DIR"
  err "Step 0 should have downloaded model artifacts. Re-run from step 0."
  exit 1
fi
info "Model artifacts found in $MODEL_DIR"

# -- Step A: Get a temporary blob storage URI for uploading -------------------
info "Requesting temporary blob storage URI from registry..."
ACCESS_TOKEN=$(az account get-access-token --query accessToken -o tsv)

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
info "Uploading model artifacts via azcopy..."
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

ACCESS_TOKEN=$(az account get-access-token --query accessToken -o tsv)

MODEL_BODY=$(cat <<EOF
{
  "properties": {
    "description": "${MODEL_NAME} with deployment template v${MODEL_VERSION}  -- azcopy upload",
    "modelType": "custom_model",
    "modelUri": "${BLOB_URI}",
    "properties": {
      "aotManifest": "True"
    },
    "tags": {
      "source": "huggingface",
      "hf_model_id": "${HF_MODEL_ID}",
      "framework": "transformers"
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

# -- Patch DTs on the newly created model -------------------------------------
patch_model_dts

# -- Verify -------------------------------------------------------------------
info "Verifying model in registry..."
az ml model show \
  --name "$MODEL_NAME" \
  --version "$MODEL_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -o json 2>/dev/null

verify_model_dts

# List model artifacts in blob storage to confirm file/dir layout
info "Listing model artifacts in blob storage..."
azcopy list "$SAS_URI" --machine-readable 2>/dev/null || azcopy list "$SAS_URI" 2>/dev/null || warn "azcopy list failed"

_step_end
