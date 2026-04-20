# Azure ML Deployment Templates — E2E CLI

Deploy any HuggingFace model to Azure ML managed online endpoints using
**deployment templates** — reusable, versioned definitions of environment,
probes, scoring configuration, and vLLM runtime settings registered in an
Azure ML registry.

## Quick Start

```bash
# Deploy Qwen 3.5 0.8B on H100 + A100 (single GPU each)
bash scripts/run-e2e-cli.sh \
  --hf-model Qwen/Qwen3.5-0.8B \
  --version 1 \
  --sku Standard_NC40ads_H100_v5 \
  --sku Standard_NC24ads_A100_v4

# Deploy Gemma 4 31B on 2-GPU SKUs
bash scripts/run-e2e-cli.sh \
  --hf-model google/gemma-4-31B-it \
  --version 1 \
  --sku Standard_NC80adis_H100_v5 \
  --sku Standard_NC48ads_A100_v4

# Reuse an existing environment (skip Docker build)
bash scripts/run-e2e-cli.sh \
  --hf-model google/gemma-4-31B-it \
  --env-name vllm-server --env-version 1 \
  --version 1 \
  --sku Standard_NC80adis_H100_v5
```

## CLI Reference

```
scripts/run-e2e-cli.sh [OPTIONS]

Required:
  --hf-model <id>          HuggingFace model ID (e.g. Qwen/Qwen3.5-0.8B)

Optional:
  --version <N>            Set all asset versions (model, env, DT) to N
  --model-version <N>      Override model version only
  --env-name <name>        Override environment name (default: vllm-server)
  --env-version <N>        Override environment version only
  --dt-version <N>         Override deployment template version only
  --sku <sku>              Target SKU (repeatable for multi-SKU deploy)

Supported SKUs:
  Standard_NC24ads_A100_v4    1× A100 80GB
  Standard_NC48ads_A100_v4    2× A100 80GB
  Standard_NC40ads_H100_v5    1× H100 80GB
  Standard_NC80adis_H100_v5   2× H100 80GB

If no --sku is specified, both a100 and h100 (single GPU) are deployed.
```

### Version Priority

Per-asset flags take precedence over `--version`, which takes precedence over
`config.sh` defaults. For a model with `config.sh` pinning `MODEL_VERSION=50`:

| Flags | model | env | dt |
|---|---|---|---|
| _(none)_ | 50 | 1 | 50 |
| `--version 51` | 51 | 51 | 51 |
| `--version 51 --env-version 60` | 51 | 60 | 51 |
| `--model-version 99` | 99 | 1 | 50 |

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Azure ML Registry                                           │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐    │
│  │ Environment    │  │ Deployment    │  │ Model         │    │
│  │ vllm-server   │◄─│ Template      │◄─│ qwen--qwen3-  │    │
│  │ (Dockerfile   │  │ vllm-qwen--   │  │ 5-0-8b        │    │
│  │  + vllm-      │  │ qwen3-5-0-8b  │  │ (DT link)     │    │
│  │  run.sh)      │  │               │  │               │    │
│  └───────────────┘  └───────┬───────┘  └───────────────┘    │
└─────────────────────────────┼────────────────────────────────┘
                              │
┌─────────────────────────────▼────────────────────────────────┐
│  Azure ML Workspace                                          │
│  ┌───────────────┐  ┌───────────────┐                        │
│  │ Endpoint      │──│ Deployment    │                        │
│  │ qwen--qwen3-  │  │ qwen--qwen3-  │                        │
│  │ 5-0-8b-h100   │  │ 5-0-8b-vllm   │                        │
│  └───────────────┘  └───────────────┘                        │
└──────────────────────────────────────────────────────────────┘
```

The **environment is model-agnostic** (`vllm-server`) — it's the same
`vllm/vllm-openai:latest` + runit container for all models. The
**deployment template** binds environment + vLLM settings + probes per model.
The **deployment** only references the model; the DT provides everything else.

## Pipeline Steps

The E2E runner executes 8 steps in sequence. Steps 4–7 run parallel
sub-tasks per SKU.

| Step | Script | What it does |
|------|--------|-------------|
| 0 | `0-validate-model.sh` | Verify model exists on HF Hub, check vLLM architecture support |
| 1 | `1-create-environment.sh` | Build Docker image in workspace, promote to registry |
| 2 | `2-create-deployment-template.sh` | Create DT with auto-calculated vLLM settings |
| 3 | `3-register-model.sh` | Download model artifacts, upload via azcopy, link DT |
| 4 | `4-create-online-endpoint.sh` | Create managed online endpoints (parallel per SKU) |
| 5 | `5-create-online-deployment.sh` | Deploy model to endpoints (parallel per SKU) |
| 6 | `6-test-inference.sh` | Run llm-api-spec API compatibility checks (debug mode) |
| 7 | `7-benchmark.sh` | Run AIPerf benchmarks across concurrency/token configs |

Steps skip automatically when the asset already exists — the summary shows
`SKIPPED (asset already exists)` vs `CREATED` for each step and sub-task.

### Summary Output

After completion, `summary.txt` is written to the log directory:

```
======================================================================
[SUMMARY] CLI E2E Run -- 2026-04-18_14-12-05 -- model=Qwen/Qwen3.5-0.8B
======================================================================
  SKUs:       h100 a100
  Versions:   model=50  env=50  dt=50
  Total time: 52m 15s
  Passed: 8 / 8
  Failed: 0 / 8
----------------------------------------------------------------------
  STEP                                      TIME  STATUS    ACTION
  ----                                      ----  ------    ------
  0-validate-model                           0m 01s  [PASS]   CREATED
  1-create-environment                       0m 02s  [PASS]   SKIPPED (asset already exists)
  2-create-deployment-template               0m 01s  [PASS]   SKIPPED (asset already exists)
  3-register-model                           2m 21s  [PASS]   CREATED
  4-create-online-endpoint                   1m 17s  [PASS]   CREATED
    └─ a100                                  1m 12s            CREATED
    └─ h100                                  1m 15s            CREATED
  5-create-online-deployment                40m 05s  [PASS]   CREATED
    └─ a100                                 38m 42s            CREATED
    └─ h100                                 40m 01s            CREATED
  6-test-inference                           0m 12s  [PASS]   CREATED
  7-benchmark                                8m 16s  [PASS]   CREATED
======================================================================
```

## Step 0: Model Validation & vLLM Compatibility

Before any Azure resources are created, step 0 validates the model:

1. **HuggingFace Hub check** — Queries `https://huggingface.co/api/models/<id>`
   to confirm the model exists. Reports if the model is gated or private
   (requires `HF_TOKEN`).

2. **Architecture extraction** — Reads `config.architectures` from the HF API
   response (e.g. `Qwen3ForCausalGeneration`, `Gemma4ForConditionalGeneration`).

3. **vLLM registry lookup** — Fetches
   [`vllm/model_executor/models/registry.py`](https://github.com/vllm-project/vllm/blob/main/vllm/model_executor/models/registry.py)
   from GitHub and checks if the model's architecture key appears in the
   registry dictionaries. Results:

   - **Native support** — Architecture found in the registry. Full optimized
     inference path.
   - **No native match** — A warning is emitted, but the pipeline continues.
     vLLM's Transformers backend may still serve the model (typically within
     ~5% of native performance). If the model truly can't load, step 5 will
     fail at deployment time.

4. **Metadata report** — Logs `pipeline_tag` (e.g. `text-generation`,
   `image-text-to-text`), `library_name`, and gated/private status.

```
$ HF_MODEL_ID="google/gemma-4-31B-it" bash scripts/cli/0-validate-model.sh
[INFO]  Model found on HuggingFace Hub.
[INFO]  Model architecture(s):
[INFO]    - Gemma4ForConditionalGeneration
[INFO]  Architecture 'Gemma4ForConditionalGeneration' is natively supported by vLLM.
[INFO]  Pipeline tag: image-text-to-text
[INFO]  Library: transformers
```

## Step 1: Create the Environment

The environment wraps vLLM in a Docker image with runit process supervision,
required by Azure ML managed endpoints.

Key design decisions:
- **Base image:** `vllm/vllm-openai:latest` — provides vLLM + CUDA + PyTorch
- **No nginx:** vLLM serves directly on port 8000 (the DT's `scoring_port`)
- **Strict offline:** `HF_HUB_OFFLINE=1` — no model downloads at runtime
- **`ENTRYPOINT []`:** Clears base image entrypoint so runit runs as PID 1

Create in workspace first (builds the Docker image in the workspace ACR),
then share to registry:

```bash
# Create in workspace (triggers Docker image build)
az ml environment create \
  --file yaml/environment.yml \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP"

# Wait for image build (~15 min), then promote to registry
az ml environment share \
  --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
  --share-with-name "$ENVIRONMENT_NAME" --share-with-version "$ENVIRONMENT_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP"
```

<details>
<summary>Example output (Step 1)</summary>

```json
{
  "build": {
    "dockerfile_path": "Dockerfile",
    "path": "https://....blob.core.windows.net/.../yaml"
  },
  "description": "vLLM inference server (model-agnostic)",
  "id": "azureml://registries/mabables-reg-feb26/environments/vllm-server/versions/50",
  "name": "vllm-server",
  "os_type": "linux",
  "tags": {
    "framework": "vllm",
    "base_image": "vllm-openai"
  },
  "version": "50"
}
```

</details>

## Step 2: Auto-Calculated vLLM Settings

Step 2 calls `calc-vllm-config.sh` to compute optimal vLLM parameters from the
model's `config.json` and the target GPU. These values are baked into the
deployment template.

### Deployment template fields

The deployment template defines everything the endpoint needs to serve the model:

| Field | Value | Why |
|-------|-------|-----|
| `scoring_port` | 8000 | vLLM's native HTTP port |
| `scoring_path` | `/v1` | OpenAI-compatible API root |
| `model_mount_path` | `/opt/ml/model` | Where Azure ML mounts model artifacts |
| `liveness_probe` | `GET /health:8000` | vLLM's health check endpoint |
| `readiness_probe` | `GET /health:8000` | Same — vLLM is ready when healthy |
| `initial_delay` | 600s | GPU model loading can take 5–10 min |
| `request_timeout_ms` | 90000 | Long responses need generous timeout |
| `max_concurrent_requests` | 250 | vLLM handles batching internally |
| `environment_variables` | `VLLM_*`, `HF_HUB_OFFLINE` | Runtime config for vLLM |

```bash
az ml deployment-template create \
  --file yaml/deployment-template.yml \
  --registry-name "$AZUREML_REGISTRY"
```

<details>
<summary>Example output (Step 2)</summary>

```json
{
  "allowedInstanceTypes": [
    "Standard_NC24ads_A100_v4",
    "Standard_NC48ads_A100_v4",
    "Standard_NC40ads_H100_v5",
    "Standard_NC80adis_H100_v5"
  ],
  "defaultInstanceType": "Standard_NC40ads_H100_v5",
  "deploymentTemplateType": "managed",
  "description": "vLLM deployment template for Qwen/Qwen3.5-0.8B",
  "environmentId": "azureml://registries/mabables-reg-feb26/environments/vllm-server/versions/50",
  "environmentVariables": {
    "HF_HOME": "/tmp/hf_cache",
    "HF_HUB_OFFLINE": "1",
    "TRANSFORMERS_OFFLINE": "1",
    "VLLM_GPU_MEMORY_UTILIZATION": "0.9",
    "VLLM_MAX_MODEL_LEN": "131072",
    "VLLM_MAX_NUM_SEQS": "256",
    "VLLM_NO_USAGE_STATS": "1",
    "VLLM_TENSOR_PARALLEL_SIZE": "1"
  },
  "instanceCount": 1,
  "livenessProbe": {
    "httpMethod": "GET",
    "initialDelay": "PT10M",
    "path": "/health",
    "port": 8000,
    "scheme": "http"
  },
  "modelMountPath": "/opt/ml/model",
  "name": "vllm-qwen--qwen3-5-0-8b",
  "requestSettings": {
    "maxConcurrentRequestsPerInstance": 250,
    "requestTimeout": "PT1M30S"
  },
  "scoringPath": "/v1",
  "scoringPort": 8000,
  "version": "50"
}
```

</details>

### What it computes

| Parameter | How it's calculated |
|---|---|
| `VLLM_TENSOR_PARALLEL_SIZE` | Minimum GPUs to fit model weights with ≥15% headroom for KV cache. Doubles TP until `model_gb / TP ≤ 85%` of per-GPU budget. Clamped to available GPUs in the SKU. |
| `VLLM_MAX_MODEL_LEN` | Maximum context length that fits in remaining VRAM after model weights. KV cache budget = `(gpu_vram × mem_util - model_gb/TP - overhead)`. Per-token KV cost accounts for GQA (grouped-query attention), sliding vs full attention layers, and different head dimensions. Clamped to `max_position_embeddings` and rounded to power of 2. |
| `VLLM_GPU_MEMORY_UTILIZATION` | `0.9` for TP=1, `0.85` for TP>1 (NCCL buffer headroom). |
| `VLLM_MAX_NUM_SEQS` | `kv_budget_tokens / avg_seq_len`, clamped to [1, 256]. |

### Model config fields used

The calculator reads these from `config.json` (or `text_config` for multimodal
models):

- `hidden_size`, `num_hidden_layers`, `num_attention_heads`
- `num_key_value_heads` (GQA), `head_dim`
- `max_position_embeddings`, `vocab_size`
- `layer_types` (for hybrid sliding/full attention like Gemma 4)
- `model.safetensors.index.json → metadata.total_size` (exact weight size)

### Standalone usage

```bash
# From model artifacts directory
bash scripts/calc-vllm-config.sh --sku Standard_NC40ads_H100_v5

# With explicit config path
bash scripts/calc-vllm-config.sh \
  --config /path/to/config.json \
  --sku Standard_NC80adis_H100_v5

# Get shell-sourceable exports
eval "$(bash scripts/calc-vllm-config.sh --export --sku Standard_NC40ads_H100_v5)"
```

Example output:

```
========================================================================
  vLLM Config Calculator
========================================================================
  GPU:    H100 80GB × 1    (SKU: Standard_NC40ads_H100_v5)
  Model:  models/qwen--qwen3-5-0-8b/model-artifacts/config.json
  Detail: model=1.62GB kv_budget=69.88GB/gpu kv_per_tok=15360B max_kv_tok=4886938 seq_len=4096

  ┌──────────────────────────────────┬──────────┐
  │  Parameter                       │  Value   │
  ├──────────────────────────────────┼──────────┤
  │  VLLM_TENSOR_PARALLEL_SIZE       │  1       │
  │  VLLM_MAX_MODEL_LEN              │  131072  │
  │  VLLM_GPU_MEMORY_UTILIZATION      │  0.9     │
  │  VLLM_MAX_NUM_SEQS               │  256     │
  └──────────────────────────────────┴──────────┘
```

### SKU → GPU mapping

| Azure SKU | GPUs | GPU Type |
|---|---|---|
| `Standard_NC24ads_A100_v4` | 1 | A100 80GB |
| `Standard_NC48ads_A100_v4` | 2 | A100 80GB |
| `Standard_NC40ads_H100_v5` | 1 | H100 80GB |
| `Standard_NC80adis_H100_v5` | 2 | H100 80GB |
| `Standard_ND96isr_H100_v5` | 8 | H100 80GB |
| `Standard_ND96amsr_A100_v4` | 8 | A100 80GB |

## Step 3: Register the Model

The model includes two important fields:
- **`properties.aotManifest: "True"`** — required for the service to recognize model artifacts
- **`default_deployment_template`** — links model → DT so deployments auto-inherit settings

> **Note:** We use `azcopy` + REST API instead of `az ml model create` because the
> CLI's built-in upload uses single-threaded Python blob uploads which fail with
> BrokenPipeError on large model files (>1 GB). See `3-register-model.sh` for details.

```bash
# The automated script handles: HF download → azcopy upload → REST registration → DT PATCH.
# For reference, the equivalent CLI command (not used due to large file issues):
#
#   az ml model create \
#     --file yaml/model.yml \
#     --registry-name "$AZUREML_REGISTRY"
```

Verify the DT link:

```bash
az ml model show \
  --name "$MODEL_NAME" --version "$MODEL_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  --query "default_deployment_template.asset_id" -o tsv
# Expected: azureml://registries/.../deploymentTemplates/vllm-<slug>/versions/<N>
```

<details>
<summary>Example output (Step 3)</summary>

```
[START] Step 3: Register model
[INFO]  Model artifacts already exist in model-artifacts -- skipping download.
[INFO]  Uploading model artifacts via azcopy...
```
azcopy upload summary:
```
Elapsed Time (Minutes): 2.35
Number of File Transfers: 13
Number of File Transfers Completed: 13
Number of File Transfers Failed: 0
Total Number of Bytes Transferred: 1769981816
Final Job Status: Completed
```
```
[INFO]  Creating model asset via REST...
[INFO]  Associating deployment template with model via PATCH...
[INFO]  Deployment template patched on model.
```
```json
{
  "default_deployment_template": {
    "asset_id": "azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-qwen--qwen3-5-0-8b/versions/50"
  },
  "id": "azureml://registries/mabables-reg-feb26/models/qwen--qwen3-5-0-8b/versions/50",
  "name": "qwen--qwen3-5-0-8b",
  "tags": {
    "hf_model_id": "Qwen/Qwen3.5-0.8B",
    "framework": "transformers",
    "source": "huggingface"
  },
  "type": "custom_model",
  "version": "50"
}
```

</details>

## Step 4: Create the Endpoint

One endpoint is created per SKU, in parallel.

```bash
az ml online-endpoint create \
  --file yaml/endpoint-h100.yml \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP"
```

<details>
<summary>Example output (Step 4)</summary>

```json
{
  "auth_mode": "key",
  "description": "Online endpoint for Qwen/Qwen3.5-0.8B on H100",
  "name": "qwen--qwen3-5-0-8b-h100",
  "provisioning_state": "Succeeded",
  "scoring_uri": "https://qwen--qwen3-5-0-8b-h100.eastus2.inference.ml.azure.com/score"
}
```

</details>

## Step 5: Create the Deployment

The deployment YAML is minimal — it only specifies the model reference and instance
type. The deployment template (linked via the model) provides everything else:

```yaml
name: qwen--qwen3-5-0-8b-vllm
endpoint_name: qwen--qwen3-5-0-8b-h100
model: azureml://registries/mabables-reg-feb26/models/qwen--qwen3-5-0-8b/versions/50
instance_type: Standard_NC40ads_H100_v5
instance_count: 1
```

> **Important:** Environment variables set in the deployment YAML are ignored when a
> deployment template is attached. Configure all env vars in the DT instead.

```bash
az ml online-deployment create \
  --file yaml/deployment-h100.yml \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  --all-traffic
```

The CLI will detect the DT linkage and print:

```
Model 'qwen--qwen3-5-0-8b' (version 50) from registry 'mabables-reg-feb26'
has a default deployment template configured.
Default deployment template:
  azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-qwen--qwen3-5-0-8b/versions/50
```

Provisioning typically takes 15–40 minutes (GPU VM allocation + Docker image pull +
model download to GPU + vLLM server startup). Both SKUs deploy in parallel.

<details>
<summary>Example output (Step 5)</summary>

```json
{
  "endpoint_name": "qwen--qwen3-5-0-8b-h100",
  "instance_count": 1,
  "instance_type": "Standard_NC40ads_H100_v5",
  "model": "azureml://registries/mabables-reg-feb26/models/qwen--qwen3-5-0-8b/versions/50",
  "name": "qwen--qwen3-5-0-8b-vllm",
  "provisioning_state": "Succeeded",
  "type": "managed"
}
```

</details>

## Step 6: Test Inference (llm-api-spec)

Step 6 runs [llm-api-spec](https://github.com/AzureML/LLM-API-Spec) in `--debug`
mode against each deployed endpoint. This performs a comprehensive API
compatibility check covering text I/O, tool calling, streaming, structured
output, and more — far beyond a single curl request.

### How it works

1. Fetches the endpoint URL and API key at runtime via `az ml online-endpoint`
2. Builds a per-SKU target config from `templates/yaml/llm-api-spec-target.tmpl.yml`
   — the API key is injected at runtime and never stored in YAML files
3. Runs `llm-api-validate --debug --schema chat_completions`
4. Generates outputs under the timestamped log directory:
   - `6-inference-{sku}.md` — Human-readable markdown report with request/response payloads
   - `6-inference-{sku}.json` — Machine-readable JSON report
   - `6-inference-{sku}-debug.log` — Full HTTP debug trace
   - `6-inference-{sku}.log` — Console output

### Target template

The target config template at `templates/yaml/llm-api-spec-target.tmpl.yml`
contains endpoint name placeholders (`${ENDPOINT_NAME_H100}`, etc.) that are
hydrated by `hydrate_yaml`. The `base_url` and `api_key` fields use runtime
placeholders (`__BASE_URL_H100__`, `__API_KEY__`) that are replaced at
execution time — API keys are never committed to files.

### Manual run

```bash
# Run against a specific endpoint
llm-api-validate \
  --target https://my-endpoint.eastus2.inference.ml.azure.com/v1 \
  --model model \
  --api-key "$API_KEY" \
  --schema chat_completions \
  --debug \
  --output markdown \
  --output-file report.md
```

### Capability coverage

The `chat_completions` schema tests:
- `text_input` / `text_output` — basic chat completion
- `tool_calling` — function calling with tool definitions
- `tool_choice` variants — `auto`, `none`, `required`, named
- `multiple_tool_calls` / `parallel_tool_calls`
- `streaming` — SSE streaming with chunk validation
- `json_output` / `structured_output` — JSON mode and schema enforcement
- `stop_sequences` / `logprobs` / `seeded_determinism`
- `image_input` — multimodal image support (URL and base64)
- And more (see `llm-api-validate --help` for full list)

<details>
<summary>Example markdown report (Step 6, --debug mode)</summary>

```markdown
# LLM API Compatibility Report

## Summary

google--gemma-4-31b-it-h100 — 17 passed, 1 failed, 5 unsupported, 7 n/a (out of 30)

## google--gemma-4-31b-it-h100

### Chat Completions

| # | Capability | Result | Details |
|---|---|---|---|
| 1 | text_input | ✅ passed | Text input accepted and processed |
| 2 | text_output | ✅ passed | Response contains text content |
| 3 | tool_calling | ✅ passed | Tool call returned: get_weather |
| 4 | streaming | ✅ passed | Streaming produced 15 chunks |
| 5 | image_input_url | ⚠️ unsupported | 400: model does not support image input |
```

</details>

## Step 7: Benchmark

Step 7 runs [AIPerf](https://pypi.org/project/aiperf/) benchmarks across a matrix
of concurrency levels and token configurations, for each SKU in parallel.

Default benchmark matrix:
- **Concurrencies:** 1, 2, 4, 8, 16, 32, 96
- **Token configs:** 200in/200out (short), 2000in/200out (medium), 2000in/8000out (long-output), 8000in/2000out (long-prompt)
- **Total runs per SKU:** 28 (7 concurrencies × 4 token configs)

Results are saved to `logs/e2e/<timestamp>/benchmark/<sku>/` with per-run
CSV, JSON, and log files.

<details>
<summary>Example AIPerf output</summary>

```
                                NVIDIA AIPerf | LLM Metrics
┏━━━━━━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━┓
┃         Metric ┃       avg ┃      min ┃       max ┃       p99 ┃       p50 ┃
┡━━━━━━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━┩
│  Time to First │    128.34 │    97.35 │    167.38 │    165.59 │    126.11 │
│     Token (ms) │           │          │           │           │           │
│  Inter Token   │      5.71 │     4.13 │     11.32 │     10.87 │      5.56 │
│   Latency (ms) │           │          │           │           │           │
│  Output Token  │    213.20 │   189.48 │    241.94 │    239.44 │    214.57 │
│  Throughput    │           │          │           │           │           │
│  (tok/sec/u)   │           │          │           │           │           │
│  Output Token  │  3,898.48 │      N/A │       N/A │       N/A │       N/A │
│  Throughput    │           │          │           │           │           │
│  (tokens/sec)  │           │          │           │           │           │
│  Request       │      2.71 │      N/A │       N/A │       N/A │       N/A │
│  Throughput    │           │          │           │           │           │
│  (req/sec)     │           │          │           │           │           │
└────────────────┴───────────┴──────────┴───────────┴───────────┴───────────┘
```

</details>

## Environment (Model-Agnostic)

The environment (`vllm-server`) is shared across all models. It contains:

- **Base image:** `vllm/vllm-openai:latest` (vLLM + CUDA + PyTorch)
- **runit:** Process supervisor required by Azure ML managed endpoints
- **No model-specific content:** Model artifacts are mounted at deploy time

```dockerfile
FROM vllm/vllm-openai:latest
RUN apt-get update && apt-get install -y --no-install-recommends runit && \
    rm -rf /var/lib/apt/lists/*
RUN mkdir -p /var/runit/vllm
COPY vllm-run.sh /var/runit/vllm/run
RUN chmod +x /var/runit/vllm/run
ENTRYPOINT []
CMD ["runsvdir", "/var/runit"]
```

To create a model-specific environment instead:

```bash
bash scripts/run-e2e-cli.sh \
  --hf-model Qwen/Qwen3.5-0.8B \
  --env-name vllm-qwen35 \
  --version 1
```

## Directory Structure

```
azureml-deployment-templates/
├── scripts/
│   ├── run-e2e-cli.sh              # E2E pipeline runner
│   ├── env.sh                      # Environment resolver (HF_MODEL_ID → names/paths)
│   ├── calc-vllm-config.sh         # vLLM config calculator
│   ├── calc-batch-size.sh          # Batch size calculator
│   ├── plot-benchmark.py           # Benchmark visualization
│   └── cli/
│       ├── 0-validate-model.sh     # HF Hub + vLLM compat check
│       ├── 1-create-environment.sh # Docker build + registry promotion
│       ├── 2-create-deployment-template.sh
│       ├── 3-register-model.sh     # azcopy upload + REST registration
│       ├── 4-create-online-endpoint.sh
│       ├── 5-create-online-deployment.sh
│       ├── 6-test-inference.sh     # Chat completion smoke test
│       └── 7-benchmark.sh          # AIPerf multi-config benchmark
├── templates/
│   └── yaml/
│       ├── environment.tmpl.yml
│       ├── deployment-template.tmpl.yml
│       ├── model.tmpl.yml
│       ├── endpoint-{a100,h100}.tmpl.yml
│       ├── deployment-{a100,h100}.tmpl.yml
│       └── docker/
│           ├── Dockerfile
│           └── vllm-run.sh
└── models/
    └── <model-slug>/              # Auto-created per model
        ├── config.sh              # Version pins (optional)
        ├── model-artifacts/       # Downloaded HF model files
        ├── yaml/                  # Hydrated YAML (from templates)
        └── logs/
            └── e2e/<timestamp>/   # Per-run logs + summary.txt
```

## Prerequisites

- Azure CLI with `ml` extension (`az extension add -n ml`)
- An Azure ML workspace and registry
- `az login` completed
- Python 3 with `pyyaml`
- `llm-api-spec` (for step 6 inference tests): `pip install -e /path/to/LLM-API-Spec`
  — See [LLM-API-Spec](https://github.com/AzureML/LLM-API-Spec) for the API compatibility framework
- `aiperf` (for step 7 benchmarks): `pip install aiperf`

## Key Design Decisions

- **azcopy for model upload** — `az ml model create` uses single-threaded Python
  blob uploads that fail with BrokenPipeError on large files. Step 3 uses azcopy +
  REST API instead.
- **`HF_HUB_OFFLINE=1`** — No HuggingFace downloads at runtime. All model
  artifacts must be pre-uploaded.
- **`ENTRYPOINT []`** — Clears the vLLM base image entrypoint so runit runs as
  PID 1, which Azure ML requires.
- **Parallel SKU deployment** — Steps 4–7 deploy/test/benchmark across SKUs
  concurrently using background processes + `wait`.
- **YAML hydration** — Templates use `${VAR}` placeholders, hydrated by `env.sh`'s
  `hydrate_yaml()` function via a sed script file (avoids eval + special-char issues
  with model IDs containing `/`).

---

## `az ml deployment-template` CLI Reference

| Command   | Example |
|-----------|---------|
| **create** | `az ml deployment-template create --file deployment-template.yml --registry-name $REG` |
| **show**   | `az ml deployment-template show --name vllm-qwen--qwen3-5-0-8b --version 50 --registry-name $REG` |
| **list**   | `az ml deployment-template list --name vllm-qwen--qwen3-5-0-8b --registry-name $REG` |
| **update** | `az ml deployment-template update --name vllm-qwen--qwen3-5-0-8b --version 50 --set tags.status=approved --registry-name $REG` |
| **archive** | `az ml deployment-template archive --name vllm-qwen--qwen3-5-0-8b --version 50 --registry-name $REG` |
| **restore** | `az ml deployment-template restore --name vllm-qwen--qwen3-5-0-8b --version 50 --registry-name $REG` |

## SDK Reference (Python)

```python
from azure.ai.ml import MLClient
from azure.ai.ml.entities import DeploymentTemplate
from azure.identity import DefaultAzureCredential

# Connect to registry
ml = MLClient(
    credential=DefaultAzureCredential(),
    registry_name="mabables-reg-feb26",
)

# Load from YAML
from azure.ai.ml import load_deployment_template
dt = load_deployment_template(source="yaml/deployment-template.yml")
ml.deployment_templates.create_or_update(dt)

# Show
dt = ml.deployment_templates.get(name="vllm-qwen--qwen3-5-0-8b", version="50")
print(dt.environment, dt.request_settings, dt.environment_variables)

# List versions
for dt in ml.deployment_templates.list(name="vllm-qwen--qwen3-5-0-8b"):
    print(f"  v{dt.version}  {dt.description}")
```

Key SDK methods on `ml.deployment_templates`:

| Method | Description |
|--------|-------------|
| `create_or_update(dt)` | Create or update a deployment template |
| `get(name, version)` | Get a specific version |
| `list(name)` | List all versions of a deployment template |
| `archive(name, version)` | Archive (soft-delete) a version |
| `restore(name, version)` | Restore an archived version |

## Cleanup

Delete endpoints (and their deployments) when done:

```bash
az ml online-endpoint delete \
  --name "$ENDPOINT_NAME_H100" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" --yes

az ml online-endpoint delete \
  --name "$ENDPOINT_NAME_A100" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" --yes
```

> **Note:** Deleting the endpoint also deletes all deployments under it and
> deallocates the GPU VMs. Registry assets (model, DT, environment) remain
> and can be reused.
