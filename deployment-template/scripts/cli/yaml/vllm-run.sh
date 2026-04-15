#!/bin/bash
# vLLM runit service script — started by runsvdir
# Strictly offline: model MUST be mounted locally, no HF Hub downloads.
set -e

export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export VLLM_NO_USAGE_STATS=1

# AZUREML_MODEL_DIR is set by Azure ML at runtime to the model mount path
BASE="${AZUREML_MODEL_DIR:?AZUREML_MODEL_DIR is not set — model must be mounted}"

# Model artifacts may be nested; find the directory containing config.json
CONFIG=$(find "$BASE" -name config.json -maxdepth 3 2>/dev/null | head -1)
if [ -z "$CONFIG" ]; then
  echo "ERROR: No config.json found under $BASE — model artifacts missing" >&2
  exit 1
fi
MODEL_PATH=$(dirname "$CONFIG")

echo "Starting vLLM with local model at: $MODEL_PATH"
exec python3 -m vllm.entrypoints.openai.api_server \
  --model "$MODEL_PATH" \
  --tensor-parallel-size "${VLLM_TENSOR_PARALLEL_SIZE:-1}" \
  --gpu-memory-utilization "${VLLM_GPU_MEMORY_UTILIZATION:-0.9}" \
  --max-model-len "${VLLM_MAX_MODEL_LEN:-131072}" \
  --served-model-name "${VLLM_SERVED_MODEL_NAME:-model}" \
  --port 8000 \
  --host 0.0.0.0
