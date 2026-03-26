# BYOC E2E Walkthrough (From Model Choice to Live Inference)

This is the end-to-end BYOC flow, written in the exact order you would execute it:
1. Identify model (intro)
2. Identify runtime (why vLLM)
3. Wrap runtime in Dockerfile and create environment
4. Download and register model
5. Create endpoint
6. Create deployment
7. Test deployment

Real output snippets come from `byoc/logs/`.

## Prerequisites

```bash
cd /Users/mabables/CODE/REPOS/deployment-template-demo
source .venv/bin/activate
source byoc/config.sh
```

---

## 1. Identify the model 

Goal:
- Deploy a compact instruction/chat model that fits single-GPU serving for fast validation.

Model used:
- Hugging Face model: `Qwen/Qwen3.5-0.8B`
- Registry model name: `Qwen35-08B`
- BYOC model version: `5`

Why this model:
- Small enough (0.8B) for practical endpoint startup while still giving useful chat completions.
- Strong compatibility with transformer-based serving stacks.

Model metadata snippet (from `byoc/yaml/model.yml`):

```yaml
name: Qwen35-08B
version: 5
type: custom_model
description: "Qwen3.5-0.8B (BYOC — no deployment template)"
tags:
  hf_model_id: Qwen/Qwen3.5-0.8B
  parameters: "0.8B"
```

---

## 2. Identify the runtime (why vLLM)

Goal:
- Serve the model through OpenAI-compatible endpoints so clients can call `/v1/chat/completions` directly.

Runtime chosen:
- Base runtime: `vllm/vllm-openai:latest`

How vLLM was identified:
- It exposes an OpenAI-compatible API surface.
- It is optimized for high-throughput transformer inference on GPU.
- It is a standard serving runtime for Qwen-family chat models.

Evidence from successful inference response (from `byoc/logs/5-inference.log`):

```json
{
  "object": "chat.completion",
  "model": "Qwen3.5-0.8B"
}
```

---

## 3. Wrap vLLM in Dockerfile and create Azure ML environment

Why wrap vLLM:
- Azure ML managed online endpoints require `runit` (`runsvdir`) process supervision.
- Azure ML probes liveness/readiness on port `5001`; raw vLLM serves on `8000`.
- Wrapper adds `nginx` on `5001` and proxies to vLLM on `8000`.

Dockerfile key lines (from `byoc/yaml/Dockerfile`):

```dockerfile
FROM vllm/vllm-openai:latest
RUN apt-get update && apt-get install -y --no-install-recommends runit nginx
RUN mkdir -p /var/runit/vllm /var/runit/nginx
```

Create environment command:

```bash
az ml environment create \
  --file byoc/yaml/environment.yml \
  --registry-name "$AZUREML_REGISTRY"
```

Environment output snippet (from `byoc/logs/1-environment.log`):

```yaml
id: azureml://registries/mabables-reg-feb26/environments/vllm-qwen35/versions/11
name: vllm-qwen35
version: '11'
description: vLLM OpenAI-compatible inference server with runit + nginx for Azure ML managed endpoints
```

---

## 4. Download and register model

Download model artifacts locally (example):

```bash
python - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id="Qwen/Qwen3.5-0.8B",
    local_dir="model-artifacts",
    local_dir_use_symlinks=False,
)
print("Downloaded to model-artifacts/")
PY
```

Register model in registry:

```bash
az ml model create \
  --file byoc/yaml/model.yml \
  --registry-name "$AZUREML_REGISTRY"
```

Model output snippet (from `byoc/logs/2-model.log`):

```yaml
id: azureml://registries/mabables-reg-feb26/models/Qwen35-08B/versions/5
name: Qwen35-08B
version: '5'
default_deployment_template: {}
```

Note:
- `default_deployment_template: {}` means this BYOC model is not tied to a deployment template.

---

## 5. Create endpoint

Command:

```bash
az ml online-endpoint create \
  --file byoc/yaml/endpoint.yml \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP"
```

Endpoint output snippet (from `byoc/logs/3-endpoint.log`):

```yaml
name: qwen35-endpoint
provisioning_state: Succeeded
scoring_uri: https://qwen35-endpoint.eastus2.inference.ml.azure.com/score
```

---

## 6. Create deployment

Command:

```bash
az ml online-deployment create \
  --file byoc/yaml/deployment.yml \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  --all-traffic
```

Deployment output snippet (from `byoc/logs/4-deployment.log`):

```text
All traffic will be set to deployment byoc-vllm once it has been provisioned.
...
"environment": "azureml://registries/mabables-reg-feb26/environments/vllm-qwen35/versions/11",
"model": "azureml://registries/mabables-reg-feb26/models/Qwen35-08B/versions/5",
"name": "byoc-vllm",
"provisioning_state": "Succeeded",
"instance_type": "Standard_NC40ads_H100_v5"
```

---

## 7. Test deployment

### 7A) Test via curl (OpenAI-compatible REST)

```bash
ENDPOINT_URL=$(az ml online-endpoint show \
  --name "$ENDPOINT_NAME" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  --query scoring_uri -o tsv)
ENDPOINT_URL="${ENDPOINT_URL%/score}"

KEY=$(az ml online-endpoint get-credentials \
  --name "$ENDPOINT_NAME" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  --query primaryKey -o tsv)

curl -s "$ENDPOINT_URL/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{
        "model": "Qwen3.5-0.8B",
        "messages": [{"role":"user","content":"Say hello in 5 words"}],
        "max_tokens": 50,
        "temperature": 0.2
      }'
```

Output snippet (from `byoc/logs/5-inference.log`):

```json
{
  "model": "Qwen3.5-0.8B",
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "Hello! How can I help?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 18,
    "completion_tokens": 8,
    "total_tokens": 26
  }
}
```

### 7B) Test via OpenAI SDK

```bash
python byoc/scripts/test_openai_sdk.py
```

Output snippet (from `byoc/logs/6-openai-sdk.log`):

```text
--- OpenAI SDK: chat.completions.create ---
...
"model": "Qwen3.5-0.8B",
"usage": {
  "completion_tokens": 111,
  "prompt_tokens": 22,
  "total_tokens": 133
}

--- OpenAI SDK tests passed ---
```

---

## Optional: run everything in one command

```bash
bash byoc/scripts/run-e2e.sh 2>&1 | tee byoc/logs/e2e-run.log
```

Timeline snippet (from `byoc/logs/e2e-run.log`):

```text
════ [09:03:42] Step 1: Environment — vllm-qwen35 v11
════ [09:03:55] Step 2: Model — Qwen35-08B v5
════ [09:04:02] Step 3: Online Endpoint — qwen35-endpoint
════ [09:04:08] Step 4: Online Deployment — byoc-vllm
...
provisioning_state: Succeeded
...
════ [09:36:57] Step 5: Test inference via OpenAI-compatible API
════ [09:37:04] Step 6: Test inference via OpenAI SDK
```
