FROM vllm/vllm-openai:latest

# Install runit (provides runsvdir) required by Azure ML managed endpoints
RUN apt-get update && apt-get install -y --no-install-recommends runit nginx && \
    rm -rf /var/lib/apt/lists/*

# Create runit service directories
RUN mkdir -p /var/runit/vllm /var/runit/nginx

# vLLM service: starts the OpenAI-compatible API server on port 8000
# AZUREML_MODEL_DIR is set by Azure ML at runtime to the model mount path
# Model files may be in a subdirectory, so we find the directory containing config.json
RUN printf '#!/bin/bash\nBASE="${AZUREML_MODEL_DIR:-${VLLM_MODEL_NAME:-/opt/ml/model}}"\nCONFIG=$(find "$BASE" -name config.json -maxdepth 3 2>/dev/null | head -1)\nif [ -n "$CONFIG" ]; then\n  MODEL_PATH=$(dirname "$CONFIG")\nelse\n  MODEL_PATH="$BASE"\nfi\necho "Starting vLLM with model at: $MODEL_PATH"\nexec python3 -m vllm.entrypoints.openai.api_server \\\n  --model "$MODEL_PATH" \\\n  --tensor-parallel-size "${VLLM_TENSOR_PARALLEL_SIZE:-1}" \\\n  --gpu-memory-utilization "${VLLM_GPU_MEMORY_UTILIZATION:-0.9}" \\\n  --max-model-len "${VLLM_MAX_MODEL_LEN:-131072}" \\\n  --served-model-name "${VLLM_SERVED_MODEL_NAME:-model}" \\\n  --port 8000 \\\n  --host 0.0.0.0\n' > /var/runit/vllm/run && \
    chmod +x /var/runit/vllm/run

# Nginx reverse proxy on port 5001 → vLLM on port 8000
# Azure ML probes GET / on port 5001 for liveness/readiness
RUN printf 'daemon off;\nevents { worker_connections 128; }\nhttp {\n  server {\n    listen 5001;\n    location / {\n      proxy_pass http://127.0.0.1:8000;\n    }\n    location = / {\n      return 200 \"ok\";\n    }\n  }\n}\n' > /etc/nginx/nginx.conf

RUN printf '#!/bin/bash\nexec nginx -c /etc/nginx/nginx.conf\n' > /var/runit/nginx/run && \
    chmod +x /var/runit/nginx/run
