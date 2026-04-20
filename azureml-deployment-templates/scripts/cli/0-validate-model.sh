#!/usr/bin/env bash
# Step 0: Validate that the HuggingFace model exists and is supported by vLLM
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

_step_start "Step 0: Validate model (${HF_MODEL_ID})"

# =============================================================================
# 1. Verify model exists on HuggingFace Hub
# =============================================================================
info "Checking HuggingFace Hub for model: $HF_MODEL_ID"

HF_API_URL="https://huggingface.co/api/models/${HF_MODEL_ID}"
HTTP_CODE=$(curl -s -o /tmp/hf_model_resp.json -w '%{http_code}' \
              --max-time 30 "$HF_API_URL" 2>/dev/null) || HTTP_CODE="000"

if [[ "$HTTP_CODE" == "000" ]]; then
  warn "HuggingFace Hub is unreachable (network error). Skipping validation."
  _step_end
  exit 0
fi

if [[ "$HTTP_CODE" != "200" ]]; then
  error "Model '$HF_MODEL_ID' not found on HuggingFace Hub (HTTP $HTTP_CODE)."
  error "Verify the model ID is correct: https://huggingface.co/${HF_MODEL_ID}"
  exit 1
fi

info "Model found on HuggingFace Hub."

# =============================================================================
# 2. Extract architectures from model config
# =============================================================================
MODEL_ARCHS=$(python3 -c "
import json, sys
with open('/tmp/hf_model_resp.json') as f:
    m = json.load(f)
archs = m.get('config', {}).get('architectures', [])
for a in archs:
    print(a)
" 2>/dev/null) || true

if [[ -z "$MODEL_ARCHS" ]]; then
  warn "Could not determine model architectures from HuggingFace API response."
  warn "The model may still work if config.json is present in the model artifacts."
  _step_end
  exit 0
fi

info "Model architecture(s):"
while IFS= read -r arch; do
  [[ -n "$arch" ]] && info "  - $arch"
done <<< "$MODEL_ARCHS"

# =============================================================================
# 3. Fetch vLLM model registry and check native support
# =============================================================================
VLLM_REGISTRY_URL="https://raw.githubusercontent.com/vllm-project/vllm/main/vllm/model_executor/models/registry.py"
info "Fetching vLLM model registry from GitHub (main branch)..."

REGISTRY_CONTENT=$(curl -sfL --max-time 30 "$VLLM_REGISTRY_URL" 2>/dev/null) || {
  warn "Could not fetch vLLM model registry from GitHub. Skipping compatibility check."
  _step_end
  exit 0
}

# Check each architecture against the registry
NATIVE_MATCH=false
MATCHED_ARCH=""

while IFS= read -r arch; do
  [[ -z "$arch" ]] && continue
  # Architecture keys appear as "ArchName": in the registry dicts
  if echo "$REGISTRY_CONTENT" | grep -q "\"${arch}\":"; then
    NATIVE_MATCH=true
    MATCHED_ARCH="$arch"
    break
  fi
done <<< "$MODEL_ARCHS"

if $NATIVE_MATCH; then
  info "Architecture '$MATCHED_ARCH' is natively supported by vLLM."
else
  warn "No native vLLM support found for architecture(s)."
  warn "The model MAY still work via vLLM's Transformers backend (fallback)."
  warn "  - Transformers backend perf is typically within ~5% of native."
  warn "  - If deployment fails at model load, the architecture is likely unsupported."
  warn "See: https://docs.vllm.ai/en/latest/models/supported_models.html"
fi

# =============================================================================
# 4. Report additional model metadata
# =============================================================================
python3 -c "
import json
with open('/tmp/hf_model_resp.json') as f:
    m = json.load(f)
tag = m.get('pipeline_tag', '')
lib = m.get('library_name', '')
gated = m.get('gated', False)
private = m.get('private', False)
if tag:
    print(f'[INFO]  Pipeline tag: {tag}')
if lib:
    print(f'[INFO]  Library: {lib}')
if gated:
    print(f'[WARN]  Model is GATED -- ensure HF_TOKEN is set for download.')
if private:
    print(f'[WARN]  Model is PRIVATE -- ensure HF_TOKEN with read access is set.')
" 2>/dev/null || true

rm -f /tmp/hf_model_resp.json

# =============================================================================
# 5. Download model artifacts from HuggingFace
# =============================================================================
# Check for actual model weight files, not just config.json
HAS_WEIGHTS=false
if [[ -d "$MODEL_DIR" ]]; then
  for ext in safetensors bin gguf; do
    if compgen -G "$MODEL_DIR"/*."$ext" >/dev/null 2>&1; then
      HAS_WEIGHTS=true
      break
    fi
  done
fi

if $HAS_WEIGHTS; then
  info "Model weight files already exist in $MODEL_DIR -- skipping download."
else
  info "Downloading '$HF_MODEL_ID' from HuggingFace to $MODEL_DIR ..."
  mkdir -p "$MODEL_DIR"
  pip3 install -q --break-system-packages huggingface_hub 2>/dev/null || \
    pip3 install -q huggingface_hub
  python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('$HF_MODEL_ID', local_dir='$MODEL_DIR')
"
  # Remove HF download cache to avoid uploading duplicate .metadata files
  rm -rf "${MODEL_DIR}/.cache"
  info "Download complete."

  # Verify weight files were actually downloaded
  HAS_WEIGHTS=false
  for ext in safetensors bin gguf; do
    if compgen -G "$MODEL_DIR"/*."$ext" >/dev/null 2>&1; then
      HAS_WEIGHTS=true
      break
    fi
  done
  if ! $HAS_WEIGHTS; then
    error "No model weight files (.safetensors/.bin/.gguf) found after download."
    error "Check if the model requires authentication (HF_TOKEN)."
    exit 1
  fi
fi

ARTIFACT_COUNT=$(find "$MODEL_DIR" -type f | wc -l | tr -d ' ')
ARTIFACT_SIZE=$(du -sh "$MODEL_DIR" 2>/dev/null | cut -f1)
info "Model artifacts: $ARTIFACT_COUNT files, $ARTIFACT_SIZE total"

_step_end
