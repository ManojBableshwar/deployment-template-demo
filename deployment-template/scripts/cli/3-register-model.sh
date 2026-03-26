#!/usr/bin/env bash
# Step 3: Download model from HuggingFace and register in the Azure ML registry
#
# Registers the model in the REGISTRY (not workspace) so that the
# defaultDeploymentTemplate reference is persisted. The DT field is defined
# in model.yml and the CLI dataplane API serializes it correctly.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"

MODEL_DIR="$ROOT_DIR/model-artifacts"

# Check if model already exists in registry
if az ml model show --name "$MODEL_NAME" --version "$MODEL_VERSION" \
     --registry-name "$AZUREML_REGISTRY" -o none 2>/dev/null; then
  info "Model '$MODEL_NAME' v$MODEL_VERSION already exists in registry — skipping."
else
  # Download model from HuggingFace (skip if already present)
  if [[ -d "$MODEL_DIR" && "$(ls -A "$MODEL_DIR" 2>/dev/null)" ]]; then
    info "Model artifacts already exist in $MODEL_DIR — skipping download."
  else
    info "Downloading '$HF_MODEL_ID' from HuggingFace to $MODEL_DIR …"
    pip3 install -q --break-system-packages huggingface_hub
    python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('$HF_MODEL_ID', local_dir='$MODEL_DIR')
"
    info "Download complete."
  fi

  # Register model in registry using model.yml (which includes defaultDeploymentTemplate)
  # The CLI uses the dataplane API for registry models, which supports the DT field.
  info "Uploading and registering model '$MODEL_NAME' v$MODEL_VERSION in registry '$AZUREML_REGISTRY'…"
  info "(This uploads ~1.77 GB — may take 20-30 minutes)"
  az ml model create \
    --file "$SCRIPT_DIR/yaml/model.yml" \
    --registry-name "$AZUREML_REGISTRY" \
    --resource-group "$RESOURCE_GROUP"
  info "Model registered in registry with defaultDeploymentTemplate."
fi

info "Showing details:"
az ml model show \
  --name "$MODEL_NAME" \
  --version "$MODEL_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -o json
