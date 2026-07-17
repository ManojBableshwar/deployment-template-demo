#!/usr/bin/env bash
# ==============================================================================
# 1-create-environment.sh -- Create AzureML environment (builds Docker image)
#
# The environment is created in the registry. AzureML builds the Docker image
# from the provided Dockerfile and build context.
#
# Build context includes:
#   - Dockerfile (installs Truss server, model code, runit)
#   - config.yaml (Truss model config)
#   - model/ (model code)
#   - model-weights/ (symlink or copy of Qwen3.5-0.8B weights)
#   - runit-truss.sh (runit service script)
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 1: Create AzureML Environment ==="
info "Environment: $TRUSS_ENVIRONMENT_NAME:$TRUSS_ENVIRONMENT_VERSION"

# -- Prepare build context -----------------------------------------------------
# We use `truss image build-context` to generate the server code and dependencies,
# then overlay our custom Dockerfile (with runit + HF download) and runit script.
BUILD_CONTEXT="$POC_ROOT/.build-context"
info "Generating Truss build context..."

rm -rf "$BUILD_CONTEXT"
truss image build-context "$BUILD_CONTEXT" "$POC_ROOT/truss-model" --non-interactive
ok "Truss build context generated at: $BUILD_CONTEXT"

# Overlay our AzureML-adapted Dockerfile and runit script
info "Overlaying AzureML adaptations (Dockerfile + runit)..."
cp "$DOCKER_DIR/Dockerfile" "$BUILD_CONTEXT/Dockerfile"
cp "$DOCKER_DIR/runit-truss.sh" "$BUILD_CONTEXT/runit-truss.sh"

# Add .amlignore to prevent AzureML from honoring .gitignore
printf '__pycache__\n*.pyc\n.git\nbuild_hash\n' > "$BUILD_CONTEXT/.amlignore"

ok "Build context ready ($(ls "$BUILD_CONTEXT" | wc -l | tr -d ' ') items)"

# Note: Model weights are downloaded from HuggingFace during Docker build.
# This avoids uploading 1.6GB as part of the build context.
info "Model weights will be downloaded from HuggingFace during remote build."

# -- Check if environment already exists ---------------------------------------
if az ml environment show \
    --name "$TRUSS_ENVIRONMENT_NAME" \
    --version "$TRUSS_ENVIRONMENT_VERSION" \
    --registry-name "$AZUREML_REGISTRY" \
    -o none 2>/dev/null; then
  ok "Environment already exists: $TRUSS_ENVIRONMENT_NAME:$TRUSS_ENVIRONMENT_VERSION"
  info "To rebuild, increment TRUSS_ENVIRONMENT_VERSION."
  exit 0
fi

# -- Create environment in registry --------------------------------------------
info "Creating environment in registry (remote Docker build)..."
info "This may take 10-20 minutes for the first build..."

log_cmd "1-create-environment.log" \
  az ml environment create \
    --name "$TRUSS_ENVIRONMENT_NAME" \
    --version "$TRUSS_ENVIRONMENT_VERSION" \
    --build-context "$BUILD_CONTEXT" \
    --dockerfile-path Dockerfile \
    --registry-name "$AZUREML_REGISTRY"

EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]]; then
  ok "Environment created: $TRUSS_ENVIRONMENT_NAME:$TRUSS_ENVIRONMENT_VERSION"
else
  err "Environment creation failed (exit code: $EXIT_CODE)"
  err "Check logs: $LOG_DIR/1-create-environment.log"
  exit $EXIT_CODE
fi
