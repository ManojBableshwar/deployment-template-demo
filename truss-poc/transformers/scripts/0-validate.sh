#!/usr/bin/env bash
# ==============================================================================
# 0-validate.sh -- Validate prerequisites and model artifacts
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 0: Validate prerequisites ==="

# Check Azure CLI
if ! command -v az &>/dev/null; then
  err "Azure CLI (az) not found. Install: https://aka.ms/installazurecli"
  exit 1
fi
ok "Azure CLI: $(az version --query '"azure-cli"' -o tsv)"

# Check subscription
az account set --subscription "$SUBSCRIPTION_ID"
ok "Subscription: $SUBSCRIPTION_ID"

# Check model artifacts
if [[ ! -f "$MODEL_ARTIFACTS_DIR/config.json" ]]; then
  err "Model artifacts not found at: $MODEL_ARTIFACTS_DIR"
  err "Expected config.json in that directory."
  exit 1
fi
MODEL_SIZE=$(du -sh "$MODEL_ARTIFACTS_DIR" | cut -f1)
ok "Model artifacts: $MODEL_ARTIFACTS_DIR ($MODEL_SIZE)"

# Check truss
if ! python3 -c "import truss" 2>/dev/null; then
  warn "Truss Python package not installed. Install: pip install truss"
fi

# Check docker (for local build validation only)
if command -v docker &>/dev/null; then
  ok "Docker: $(docker --version | head -1)"
else
  warn "Docker not available locally (not required — AzureML builds remotely)"
fi

# Verify workspace access
if az ml workspace show --name "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  ok "Workspace: $AZUREML_WORKSPACE"
else
  err "Cannot access workspace: $AZUREML_WORKSPACE"
  exit 1
fi

# Verify registry access
if az ml registry show --name "$AZUREML_REGISTRY" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  ok "Registry: $AZUREML_REGISTRY"
else
  err "Cannot access registry: $AZUREML_REGISTRY"
  exit 1
fi

info "=== Validation complete ==="
echo ""
info "Configuration:"
echo "  Subscription:    $SUBSCRIPTION_ID"
echo "  Resource Group:  $RESOURCE_GROUP"
echo "  Workspace:       $AZUREML_WORKSPACE"
echo "  Registry:        $AZUREML_REGISTRY"
echo "  Model:           $TRUSS_MODEL_NAME:$TRUSS_MODEL_VERSION"
echo "  Environment:     $TRUSS_ENVIRONMENT_NAME:$TRUSS_ENVIRONMENT_VERSION"
echo "  Template:        $TRUSS_TEMPLATE_NAME:$TRUSS_TEMPLATE_VERSION"
echo "  Endpoint:        $TRUSS_ENDPOINT_NAME"
echo "  Deployment:      $TRUSS_DEPLOYMENT_NAME"
echo "  Instance type:   $TRUSS_INSTANCE_TYPE"
echo "  Log dir:         $LOG_DIR"
