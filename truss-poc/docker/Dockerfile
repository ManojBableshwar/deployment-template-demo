# ==============================================================================
# Dockerfile for Truss model server on AzureML Managed Online Endpoints
#
# Based on the Truss-generated Dockerfile with AzureML adaptations:
#   1. Uses the official Truss server base image
#   2. Installs runit (AzureML managed endpoint requirement)
#   3. Downloads model weights from HuggingFace at build time
#   4. Overrides ENTRYPOINT to use runsvdir (AzureML requirement)
#
# Port: 8080 (INFERENCE_SERVER_PORT)
# Liveness: GET / → 200
# Readiness: GET /v1/models/model → model status
# Predict: POST /v1/models/model:predict
# ==============================================================================
ARG PYVERSION=py311
FROM baseten/truss-server-base:3.11-gpu-v0.13.0 AS truss_server

ENV PYTHON_EXECUTABLE="python3"
USER root
ENV HOME=/root
ENV APP_HOME=/app
RUN mkdir -p ${APP_HOME} /control

ENV DEBIAN_FRONTEND=noninteractive

# --- Install runit (AzureML managed endpoint requirement) ---------------------
RUN apt-get update && apt-get install -y --no-install-recommends runit \
    && rm -rf /var/lib/apt/lists/*

# --- Install uv for fast pip operations ---------------------------------------
RUN if ! command -v uv >/dev/null 2>&1; then \
    curl -LsSf --retry 5 --retry-delay 5 https://astral.sh/uv/0.10.0/install.sh | sh && \
    test -x ${HOME}/.local/bin/uv; \
fi
ENV PATH=${PATH}:${HOME}/.local/bin

# --- Install Python dependencies ---------------------------------------------
COPY --chown=root:root ./constraints.txt constraints.txt
COPY --chown=root:root ./requirements.txt requirements.txt
RUN UV_HTTP_TIMEOUT=300 uv pip install --system --break-system-packages \
    --index-strategy unsafe-best-match \
    --python $(which python3) \
    -r requirements.txt -c constraints.txt --no-cache-dir

# Upgrade transformers and torch to support Qwen3.5 model_type (requires transformers 5.x + torch 2.5+)
# Pin torch to 2.5.1+cu121 for CUDA 12.1 driver compatibility (A100 VMs have driver 12080)
RUN uv pip install --system --break-system-packages --python $(which python3) \
    "transformers>=5.0.0" "accelerate>=1.0.0" --no-cache-dir
RUN uv pip install --system --break-system-packages --python $(which python3) \
    --index-url https://download.pytorch.org/whl/cu121 \
    "torch==2.5.1+cu121" --no-cache-dir

# --- Install huggingface_hub for model download -------------------------------
RUN uv pip install --system --break-system-packages --python $(which python3) \
    "huggingface_hub>=0.24.0" --no-cache-dir

WORKDIR $APP_HOME

# --- Copy Truss server code ---------------------------------------------------
COPY --chown=root:root ./server ${APP_HOME}

# --- Copy model code ----------------------------------------------------------
COPY --chown=root:root ./model ${APP_HOME}/model
RUN mkdir -p /packages

# --- Download model weights at build time -------------------------------------
ARG HF_MODEL_ID=Qwen/Qwen3.5-0.8B
RUN python3 -c "from huggingface_hub import snapshot_download; snapshot_download('${HF_MODEL_ID}', local_dir='/app/model-weights')"

# --- Copy config --------------------------------------------------------------
COPY --chown=root:root ./config.yaml ${APP_HOME}/config.yaml

# --- runit service for Truss server -------------------------------------------
RUN mkdir -p /var/runit/truss-server
COPY --chown=root:root ./runit-truss.sh /var/runit/truss-server/run
RUN chmod +x /var/runit/truss-server/run

# --- Environment variables ----------------------------------------------------
ENV INFERENCE_SERVER_PORT=8080
ENV MODEL_WEIGHTS_PATH=/app/model-weights
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1
ENV PYTHONUNBUFFERED=1
ENV SERVER_START_CMD="python3 /app/main.py"

# --- Override entrypoint for AzureML (runsvdir) --------------------------------
ENTRYPOINT []
CMD ["runsvdir", "/var/runit"]

EXPOSE 8080
