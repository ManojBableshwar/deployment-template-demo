#!/usr/bin/env bash
# ==============================================================================
# 1-create-environment.sh -- Build the Truss docker_server + vLLM environment
#
# Truss's `docker_server` build context wraps the vLLM image with nginx (8080) +
# supervisord. Two small AzureML adaptations are overlaid:
#   1. Patch nginx to listen on 5001 (AzureML's fixed probe/scoring port)
#   2. Add vllm-launch.sh (resolves the MOUNTED model path, starts vLLM)
#
# NOTE: No runit and no weight-baking here. supervisord (Truss-generated) is the
# init process, and weights are mounted at runtime from the AzureML model.
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 1: Create AzureML Environment (Truss docker_server + vLLM) ==="
info "Environment: $TRUSS_ENVIRONMENT_NAME:$TRUSS_ENVIRONMENT_VERSION"

BUILD_CONTEXT="$POC_ROOT/.build-context"

# -- Generate the Truss docker_server build context ----------------------------
info "Generating Truss docker_server build context..."
rm -rf "$BUILD_CONTEXT"
truss image build-context "$BUILD_CONTEXT" "$TRUSS_MODEL_DIR" --non-interactive
ok "Truss build context generated"

# -- AzureML adaptation 1: patch nginx to listen on 5001 -----------------------
info "Patching nginx proxy: listen 8080 -> 5001 (AzureML probe port)..."
python3 - "$BUILD_CONTEXT/proxy.conf" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
if "listen 8080;" not in s:
    print("WARN: 'listen 8080;' not found in proxy.conf (Truss layout may have changed)", file=sys.stderr)
s = s.replace("listen 8080;", "listen 5001;")
open(p, "w").write(s)
PY
ok "nginx will listen on 5001"

# -- AzureML adaptation 2: add vllm-launch.sh + COPY it in the Dockerfile -------
info "Adding vllm-launch.sh to build context and Dockerfile..."
cp "$DOCKER_DIR/vllm-launch.sh" "$BUILD_CONTEXT/vllm-launch.sh"
python3 - "$BUILD_CONTEXT/Dockerfile" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
copy_line = "COPY --chown=root:root ./vllm-launch.sh /app/vllm-launch.sh\n"
if "vllm-launch.sh" not in s:
    # Insert the COPY just before the ENTRYPOINT line.
    s = s.replace("ENTRYPOINT [", copy_line + "ENTRYPOINT [", 1)
open(p, "w").write(s)
PY
ok "vllm-launch.sh wired into the image"

# Prevent AzureML from honoring .gitignore during upload.
printf '__pycache__\n*.pyc\n.git\nbuild_hash\n' > "$BUILD_CONTEXT/.amlignore"
ok "Build context ready ($(ls "$BUILD_CONTEXT" | wc -l | tr -d ' ') items)"

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

# -- Create environment in registry (remote ACR build) -------------------------
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
