#!/usr/bin/env bash
# Step 3: Upload model via azcopy and register in the Azure ML registry
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()   { printf '\033[1;31m[ERR]\033[0m   %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"
_step_start "Step 3: Register model"

# -- Check if model already exists --------------------------------------------
if az ml model show --name "$MODEL_NAME" --version "$MODEL_VERSION" \
     --registry-name "$AZUREML_REGISTRY" &>/dev/null; then
  info "Model '$MODEL_NAME' v$MODEL_VERSION already exists in registry  -- skipping upload."

  # Always re-patch the deployment template reference (version may have changed)
  info "Ensuring deployment template is set to $TEMPLATE_NAME v$TEMPLATE_VERSION..."
  PATCH_URL="https://${REGISTRY_LOCATION}.api.azureml.ms/modelregistry/v1.0/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/registries/${AZUREML_REGISTRY}/models/${MODEL_NAME}:${MODEL_VERSION}"
  PATCH_TOKEN=$(az account get-access-token --query accessToken -o tsv)
  EXPECTED_DT="azureml://registries/${AZUREML_REGISTRY}/deploymentTemplates/${TEMPLATE_NAME}/versions/${TEMPLATE_VERSION}"

  # Check current DT on the model
  MODEL_JSON=$(az ml model show --name "$MODEL_NAME" --version "$MODEL_VERSION" \
    --registry-name "$AZUREML_REGISTRY" -o json 2>/dev/null)
  CURRENT_DT=$(echo "$MODEL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('default_deployment_template',{}).get('asset_id',''))" 2>/dev/null || true)

  if [[ "$CURRENT_DT" == "$EXPECTED_DT" ]]; then
    info "DT on model already matches: $EXPECTED_DT -- skipping patch."
  else
    if [[ -n "$CURRENT_DT" ]]; then
      warn "DT mismatch on model: current='$CURRENT_DT'  expected='$EXPECTED_DT'"
      info "Patching deployment template to $TEMPLATE_NAME v$TEMPLATE_VERSION..."
    else
      info "No DT set on model. Patching to $TEMPLATE_NAME v$TEMPLATE_VERSION..."
    fi
    PATCH_RESP=$(curl -sS -w "\n%{http_code}" -X PATCH \
      "$PATCH_URL" \
      -H "Authorization: Bearer $PATCH_TOKEN" \
      -H "Content-Type: application/json" \
      -d '[{"op":"add","path":"/defaultDeploymentTemplate","value":{"assetId":"'"$EXPECTED_DT"'"}}]' 2>/dev/null)
    PATCH_HTTP=$(echo "$PATCH_RESP" | tail -1)
    if [[ "$PATCH_HTTP" == "200" ]]; then
      info "MFE PATCH succeeded."
    else
      warn "MFE PATCH returned HTTP $PATCH_HTTP (MFE may not resolve Dockerfile-based envs in DT)."
      warn "Response: $(echo "$PATCH_RESP" | head -n -1 | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message','unknown'))" 2>/dev/null || echo "$PATCH_RESP" | head -5)"
      warn "DT association on model is non-functional (discoverability only). Proceeding."
    fi
    echo  # newline after curl output

    # Verify the patch took effect
    MODEL_JSON=$(az ml model show --name "$MODEL_NAME" --version "$MODEL_VERSION" \
      --registry-name "$AZUREML_REGISTRY" -o json 2>/dev/null)
    VERIFY_DT=$(echo "$MODEL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('default_deployment_template',{}).get('asset_id',''))" 2>/dev/null || true)
    if [[ "$VERIFY_DT" == "$EXPECTED_DT" ]]; then
      info "DT patched and verified on model."
    else
      warn "DT verification: model shows '$VERIFY_DT' (expected '$EXPECTED_DT')."
      warn "MFE may not resolve Dockerfile-based env references in DT. This is non-blocking."
    fi
  fi

  info "Showing details:"
  echo "$MODEL_JSON"

  # Validate model artifacts: check manifest property (set during azcopy upload + register)
  MODEL_PATH=$(echo "$MODEL_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('path',''))" 2>/dev/null || true)
  if [[ -n "$MODEL_PATH" ]]; then
    # For existing models, check 'properties' field for manifest (indicates complete upload)
    HAS_MANIFEST=$(echo "$MODEL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('properties',{}).get('modelManifestPathOrUri',''))" 2>/dev/null || true)
    if [[ -n "$HAS_MANIFEST" ]]; then
      info "Registry model validated: manifest present ($HAS_MANIFEST)."
    else
      warn "No modelManifestPathOrUri in model properties — upload may be incomplete."
      warn "If deployments fail, delete and re-register the model."
    fi
  fi

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

# -- Patch: associate deployment template --------------------------------------
info "Associating deployment template with model via PATCH..."
EXPECTED_DT="azureml://registries/${AZUREML_REGISTRY}/deploymentTemplates/${TEMPLATE_NAME}/versions/${TEMPLATE_VERSION}"
PATCH_URL="https://${REGISTRY_LOCATION}.api.azureml.ms/modelregistry/v1.0/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/registries/${AZUREML_REGISTRY}/models/${MODEL_NAME}:${MODEL_VERSION}"
PATCH_TOKEN=$(az account get-access-token --query accessToken -o tsv)
curl --fail -sS -X PATCH \
  "$PATCH_URL" \
  -H "Authorization: Bearer $PATCH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{"op":"add","path":"/defaultDeploymentTemplate","value":{"assetId":"'"$EXPECTED_DT"'"}}]'
echo  # newline after curl output

# -- Verify -------------------------------------------------------------------
info "Verifying model in registry..."
MODEL_JSON=$(az ml model show \
  --name "$MODEL_NAME" \
  --version "$MODEL_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -o json)
echo "$MODEL_JSON"

# Verify DT was applied
VERIFY_DT=$(echo "$MODEL_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('default_deployment_template',{}).get('asset_id',''))" 2>/dev/null || true)
if [[ "$VERIFY_DT" != "$EXPECTED_DT" ]]; then
  err "DT patch verification FAILED after model creation!"
  err "  Expected: $EXPECTED_DT"
  err "  Got:      $VERIFY_DT"
  exit 1
fi
info "DT patched and verified: $EXPECTED_DT"

# List model artifacts in blob storage to confirm file/dir layout
info "Listing model artifacts in blob storage..."
azcopy list "$SAS_URI" --machine-readable 2>/dev/null || azcopy list "$SAS_URI" 2>/dev/null || warn "azcopy list failed"

_step_end
