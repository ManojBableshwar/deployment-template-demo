#!/usr/bin/env bash
# Step 1 (REST API): Create vLLM environment in the Azure ML workspace (Dockerfile build)
# and promote to registry.
#
# NOTE: Dockerfile-based environment creation requires uploading a Docker build
# context, which has no simple pure-REST equivalent.  We use `az ml environment
# create` for the workspace build, REST API for build-status polling, and
# `az ml environment share` for registry promotion.  The Dockerfile and
# vllm-run.sh are reused from the cli/yaml/ folder.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

CLI_YAML_DIR="$SCRIPT_DIR/../cli/yaml"

az account set --subscription "$SUBSCRIPTION_ID"
_step_start "Step 1: Create environment"

# -- Create in workspace (Dockerfile build) -----------------------------------
if az ml environment show --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
     --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" 2>&1; then
  info "Environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION already exists in workspace -- proceeding."
else
  info "Creating environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION in workspace '$AZUREML_WORKSPACE'..."
  # Reuse Dockerfile and vllm-run.sh from cli/yaml/
  az ml environment create \
    --file "$CLI_YAML_DIR/environment.yml" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP"
  info "Environment create command completed."
fi

# -- Wait for Docker image build via REST API ---------------------------------
if az ml environment show --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
     --registry-name "$AZUREML_REGISTRY" 2>&1; then
  info "Environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION already exists in registry -- skipping promotion."
else
  info "Waiting for environment image build to complete (polling every 30s, up to 1 hour)..."
  ENV_IMAGE_API="https://ml.azure.com/api/${WORKSPACE_LOCATION}/environment/v1.0/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/workspaces/${AZUREML_WORKSPACE}/environments/${ENVIRONMENT_NAME}/versions/${ENVIRONMENT_VERSION}/image?secrets=false"
  MAX_WAIT=3600
  INTERVAL=30
  ELAPSED=0
  while (( ELAPSED < MAX_WAIT )); do
    TOKEN=$(az account get-access-token --query accessToken -o tsv 2>/dev/null)
    IMAGE_EXISTS=$(curl -s -H "Authorization: Bearer $TOKEN" "$ENV_IMAGE_API" \
      | python3 -c "import sys,json; print(json.load(sys.stdin).get('imageExistsInRegistry',''))" 2>/dev/null || true)
    if [[ "$IMAGE_EXISTS" == "True" ]]; then
      info "Environment image build completed (${ELAPSED}s elapsed)."
      break
    fi
    info "Image not ready yet (${ELAPSED}s elapsed) -- waiting ${INTERVAL}s..."
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
  done
  if (( ELAPSED >= MAX_WAIT )); then
    error "Timed out waiting for environment image build after ${MAX_WAIT}s"
    exit 1
  fi

  # -- Promote to registry --------------------------------------------------
  info "Promoting environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION from workspace to registry..."
  az ml environment share \
    --name "$ENVIRONMENT_NAME" \
    --version "$ENVIRONMENT_VERSION" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --share-with-name "$ENVIRONMENT_NAME" \
    --share-with-version "$ENVIRONMENT_VERSION" \
    --registry-name "$AZUREML_REGISTRY" 2>&1
  info "Environment share command completed -- verifying it landed in registry..."

  if az ml environment show --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
       --registry-name "$AZUREML_REGISTRY" 2>&1; then
    info "Confirmed: environment exists in registry."
  else
    error "Environment share succeeded but environment not found in registry!"
    exit 1
  fi
fi

# -- Verify via REST API -----------------------------------------------------
info "Verifying registry environment via REST API:"
TOKEN=$(az account get-access-token --query accessToken -o tsv)
curl -sS \
  "${REGISTRY_BASE}/environments/${ENVIRONMENT_NAME}/versions/${ENVIRONMENT_VERSION}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -m json.tool

_step_end
