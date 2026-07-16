#!/usr/bin/env bash
# ==============================================================================
# 2-register-model.sh -- Register model in AzureML registry
#
# For the "baked-in weights" approach, this registers a minimal dummy model.
# AzureML deployment templates require a model reference even when weights
# are already in the container.
#
# For the "mounted weights" approach (milestone 2), this would upload the
# actual model artifacts via azcopy.
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 2: Register Model ==="
info "Model: $TRUSS_MODEL_NAME:$TRUSS_MODEL_VERSION"

# -- Check if model already exists ---------------------------------------------
if az ml model show \
    --name "$TRUSS_MODEL_NAME" \
    --version "$TRUSS_MODEL_VERSION" \
    --registry-name "$AZUREML_REGISTRY" \
    -o none 2>/dev/null; then
  ok "Model already exists: $TRUSS_MODEL_NAME:$TRUSS_MODEL_VERSION"
  exit 0
fi

# -- Register model ------------------------------------------------------------
info "Registering model in registry..."

log_cmd "2-register-model.log" \
  az ml model create \
    --file "$YAML_DIR/model.yml" \
    --registry-name "$AZUREML_REGISTRY" \
    --version "$TRUSS_MODEL_VERSION"

EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
  ok "Model registered: $TRUSS_MODEL_NAME:$TRUSS_MODEL_VERSION"
else
  err "Model registration failed (exit code: $EXIT_CODE)"
  err "Check logs: $LOG_DIR/2-register-model.log"
  exit $EXIT_CODE
fi
