#!/bin/bash
# ==============================================================================
# vllm-launch.sh -- vLLM startup for the Truss docker_server backend on AzureML
#
# Started by supervisord (Truss-generated) as the "model-server" process.
# Mirrors the repo's manual vllm-run.sh, but:
#   - No runit (supervisord owns process supervision here)
#   - Resolves weights from the MOUNTED AzureML model (no baked-in weights)
#
# vLLM listens on 8000 (internal); Truss's nginx proxy (patched to 5001) fronts
# it for AzureML probes/scoring.
# ==============================================================================
set -e

echo "===== vLLM (Truss docker_server) startup ====="
echo "AZUREML_MODEL_DIR=${AZUREML_MODEL_DIR:-<not set>}"
echo "model_mount_path (DT)=/opt/ml/model"

# -- Resolve the mounted model path (NO baked-in weights) ----------------------
# Priority: AZUREML_MODEL_DIR (if it contains config.json) -> /opt/ml/model.
# Model artifacts may be nested; find the dir containing config.json.
BASE="${AZUREML_MODEL_DIR:-/opt/ml/model}"
if [ ! -f "$BASE/config.json" ]; then
  FOUND="$(find "$BASE" /opt/ml/model -maxdepth 3 -name config.json 2>/dev/null | head -1)"
  if [ -n "$FOUND" ]; then
    BASE="$(dirname "$FOUND")"
  fi
fi
MODEL_PATH="$BASE"

echo "Resolved MODEL_PATH=$MODEL_PATH"
if [ ! -f "$MODEL_PATH/config.json" ]; then
  echo "ERROR: no config.json under mounted model path '$MODEL_PATH'." >&2
  echo "Mounted weights missing — is the AzureML model mounted at model_mount_path?" >&2
  ls -laR /opt/ml 2>/dev/null | head -40 >&2
  exit 1
fi
echo "Model files:"
ls -la "$MODEL_PATH" | head -20

# -- Optional tool-calling support ---------------------------------------------
TOOL_CALL_ARGS=()
if [ -n "${VLLM_TOOL_CALL_PARSER:-}" ]; then
  TOOL_CALL_ARGS+=(--enable-auto-tool-choice --tool-call-parser "$VLLM_TOOL_CALL_PARSER")
fi

# -- Start vLLM OpenAI server (internal port 8000) -----------------------------
echo "Starting vLLM OpenAI server on :8000 with mounted model at $MODEL_PATH"
exec python3 -m vllm.entrypoints.openai.api_server \
  --model "$MODEL_PATH" \
  --served-model-name "${VLLM_SERVED_MODEL_NAME:-model}" \
  --tensor-parallel-size "${VLLM_TENSOR_PARALLEL_SIZE:-1}" \
  --gpu-memory-utilization "${VLLM_GPU_MEMORY_UTILIZATION:-0.9}" \
  --max-model-len "${VLLM_MAX_MODEL_LEN:-8192}" \
  --max-num-seqs "${VLLM_MAX_NUM_SEQS:-256}" \
  "${TOOL_CALL_ARGS[@]}" \
  --port 8000 \
  --host 0.0.0.0
