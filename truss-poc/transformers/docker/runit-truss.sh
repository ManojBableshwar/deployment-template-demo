#!/bin/bash
# runit service script for Truss model server
# Started by runsvdir (AzureML managed endpoint requirement)
set -e

echo "===== Truss server startup diagnostics ====="
echo "INFERENCE_SERVER_PORT=${INFERENCE_SERVER_PORT:-8080}"
echo "AZUREML_MODEL_DIR=${AZUREML_MODEL_DIR:-<not set>}"
echo "MODEL_WEIGHTS_PATH=${MODEL_WEIGHTS_PATH:-/app/model-weights}"
echo "HF_HUB_OFFLINE=${HF_HUB_OFFLINE}"
echo "TRANSFORMERS_OFFLINE=${TRANSFORMERS_OFFLINE}"
echo "GPU available: $(python3 -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || echo 'unknown')"
echo "============================================="

# If AZUREML_MODEL_DIR is set (mounted model), log it.
# The model.py code handles the fallback logic:
#   AZUREML_MODEL_DIR (if has config.json) → MODEL_WEIGHTS_PATH → /app/model-weights
if [ -n "${AZUREML_MODEL_DIR}" ]; then
    echo "[runit-truss] AzureML model dir: ${AZUREML_MODEL_DIR}"
    echo "[runit-truss] Model code will check for config.json before using this path"
fi

cd /app

# Start the Truss server (uses INFERENCE_SERVER_PORT env var, default 8080)
exec python3 -c "
from truss_server import TrussServer
import os

port = int(os.environ.get('INFERENCE_SERVER_PORT', '8080'))
print(f'[runit-truss] Starting Truss server on port {port}')
server = TrussServer(port, 'config.yaml')
server.start()
"
