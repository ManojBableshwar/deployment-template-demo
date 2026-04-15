#!/usr/bin/env bash
# Step 1: Create vLLM environment in the Azure ML workspace (with Dockerfile build)
# Also creates in registry for deployment template reference.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"
_step_start "Step 1: Create environment"

# Create in workspace (Dockerfile build — needed for deployment)
if az ml environment show --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
     --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" 2>&1; then
  info "Environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION already exists in workspace — proceeding."
else
  info "Creating environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION in workspace '$AZUREML_WORKSPACE'…"
  az ml environment create \
    --file "$SCRIPT_DIR/yaml/environment.yml" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP"
  info "Environment create command completed."
fi

# Promote environment to registry (by sharing from workspace)
# The Docker image build is async — we must wait for it to materialize in ACR before sharing.
# NOTE: The ARM API and CLI do not expose build status. We use the Studio internal
#       environment image API to poll for imageExistsInRegistry.
#       See bugs/env-build-status-not-exposed.md for details.
if az ml environment show --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
     --registry-name "$AZUREML_REGISTRY" 2>&1; then
  info "Environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION already exists in registry — skipping promotion."
else
  # Poll the environment image API for build completion
  info "Waiting for environment image build to complete (polling every 30s, up to 1 hour)…"
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
    info "Image not ready yet (${ELAPSED}s elapsed) — waiting ${INTERVAL}s…"
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
  done
  if (( ELAPSED >= MAX_WAIT )); then
    error "Timed out waiting for environment image build after ${MAX_WAIT}s"
    exit 1
  fi

  info "Promoting environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION from workspace to registry…"
  az ml environment share \
    --name "$ENVIRONMENT_NAME" \
    --version "$ENVIRONMENT_VERSION" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --share-with-name "$ENVIRONMENT_NAME" \
    --share-with-version "$ENVIRONMENT_VERSION" \
    --registry-name "$AZUREML_REGISTRY" 2>&1
  info "Environment share command completed — verifying it landed in registry…"

  # Verify the environment actually exists in registry after share
  if az ml environment show --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
       --registry-name "$AZUREML_REGISTRY" 2>&1; then
    info "Confirmed: environment exists in registry."
  else
    error "Environment share succeeded but environment not found in registry!"
    exit 1
  fi
fi

info "Showing registry environment:"
az ml environment show \
  --name "$ENVIRONMENT_NAME" \
  --version "$ENVIRONMENT_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -o json

_step_end
