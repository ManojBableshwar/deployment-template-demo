#!/usr/bin/env bash
# ==============================================================================
# 3-create-deployment-template.sh -- Create deployment template in registry
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 3: Create Deployment Template ==="
info "Template: $TRUSS_TEMPLATE_NAME:$TRUSS_TEMPLATE_VERSION"

# -- Check if DT already exists ------------------------------------------------
if az ml deployment-template show \
    --name "$TRUSS_TEMPLATE_NAME" \
    --version "$TRUSS_TEMPLATE_VERSION" \
    --registry-name "$AZUREML_REGISTRY" \
    -o none 2>/dev/null; then
  ok "Deployment template already exists: $TRUSS_TEMPLATE_NAME:$TRUSS_TEMPLATE_VERSION"
  exit 0
fi

# -- Create deployment template ------------------------------------------------
info "Creating deployment template in registry..."

log_cmd "3-create-deployment-template.log" \
  az ml deployment-template create \
    --file "$YAML_DIR/deployment-template.yml" \
    --registry-name "$AZUREML_REGISTRY" \
    --version "$TRUSS_TEMPLATE_VERSION"

EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
  ok "Deployment template created: $TRUSS_TEMPLATE_NAME:$TRUSS_TEMPLATE_VERSION"
else
  err "Deployment template creation failed (exit code: $EXIT_CODE)"
  err "Check logs: $LOG_DIR/3-create-deployment-template.log"
  exit $EXIT_CODE
fi
