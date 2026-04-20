#!/bin/bash
# vLLM runit service script -- started by runsvdir
# Strictly offline: model MUST be mounted locally, no HF Hub downloads.
set -e

# HF_HUB_OFFLINE, TRANSFORMERS_OFFLINE, VLLM_NO_USAGE_STATS are set via
# the deployment template's environmentVariables -- no need to export here.

# -- Debug: dump mount & env info --
echo "===== vLLM startup diagnostics ====="
echo "AZUREML_MODEL_DIR=${AZUREML_MODEL_DIR:-<not set>}"
echo "model_mount_path (DT default)=/opt/ml/model"

# Fall back to /opt/ml/model if AZUREML_MODEL_DIR is not set
BASE="${AZUREML_MODEL_DIR:-/opt/ml/model}"
echo "Resolved BASE=$BASE"

# Check if the base path exists and what's in it
if [ -d "$BASE" ]; then
  echo "✓ $BASE exists (directory)"
  echo "Contents (depth 2):"
  find "$BASE" -maxdepth 2 -type f | head -30
  echo "Total files: $(find "$BASE" -type f | wc -l | tr -d ' ')"
  echo "Total size: $(du -sh "$BASE" 2>/dev/null | cut -f1)"
else
  echo "✗ $BASE does NOT exist"
  echo "Listing potential model mount points:"
  ls -la /opt/ml/ 2>/dev/null || echo "  /opt/ml/ does not exist"
  mount | grep -E 'fuse|blobfuse|nfs|cifs' || echo "  No fuse/nfs/cifs mounts found"
fi
echo "===================================="

# Model artifacts may be nested; find the directory containing config.json
CONFIG=$(find "$BASE" -name config.json -maxdepth 3 2>/dev/null | head -1)
if [ -z "$CONFIG" ]; then
  echo "ERROR: No config.json found under $BASE -- model artifacts missing" >&2
  echo "Searched: find $BASE -name config.json -maxdepth 3" >&2
  echo "Directory listing of $BASE:" >&2
  ls -laR "$BASE" 2>&1 | head -50 >&2
  exit 1
fi
MODEL_PATH=$(dirname "$CONFIG")

echo "Found config.json at: $CONFIG"
echo "MODEL_PATH=$MODEL_PATH"
echo "Key model files:"
for f in config.json tokenizer.json tokenizer_config.json model.safetensors.index.json; do
  if [ -f "$MODEL_PATH/$f" ]; then
    echo "  ✓ $f ($(stat -f%z "$MODEL_PATH/$f" 2>/dev/null || stat -c%s "$MODEL_PATH/$f" 2>/dev/null) bytes)"
  else
    echo "  ✗ $f MISSING"
  fi
done

export VLLM_LOGGING_LEVEL=DEBUG

# Build tool-calling flags conditionally.
# Set VLLM_TOOL_CALL_PARSER in the deployment template to enable tool calling
# for models that support it (e.g. "gemma4", "hermes", "llama3_json", "mistral").
TOOL_CALL_ARGS=()
if [ -n "${VLLM_TOOL_CALL_PARSER:-}" ]; then
  echo "Tool calling enabled: parser=${VLLM_TOOL_CALL_PARSER}"
  TOOL_CALL_ARGS+=(--enable-auto-tool-choice --tool-call-parser "$VLLM_TOOL_CALL_PARSER")
else
  echo "Tool calling disabled (VLLM_TOOL_CALL_PARSER not set)"
fi

echo "Starting vLLM with local model at: $MODEL_PATH"
exec python3 -m vllm.entrypoints.openai.api_server \
  --model "$MODEL_PATH" \
  --tensor-parallel-size "${VLLM_TENSOR_PARALLEL_SIZE:-1}" \
  --gpu-memory-utilization "${VLLM_GPU_MEMORY_UTILIZATION:-0.9}" \
  --max-model-len "${VLLM_MAX_MODEL_LEN:-131072}" \
  --max-num-seqs "${VLLM_MAX_NUM_SEQS:-256}" \
  --served-model-name "${VLLM_SERVED_MODEL_NAME:-model}" \
  "${TOOL_CALL_ARGS[@]}" \
  --port 8000 \
  --host 0.0.0.0
