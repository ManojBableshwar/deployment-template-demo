# Deployment Template E2E Walkthrough

Deploy a HuggingFace model (Qwen3.5-0.8B) to an Azure ML managed online endpoint
using a **deployment template** — a reusable definition of environment, probes,
scoring port, and runtime configuration registered in an Azure ML registry.

> **Automated runner:** All steps below can be run automatically via
> `./scripts/run-e2e-cli.sh`. Edit `configs/e2e-config.sh` to change versions,
> names, or Azure resources. This walkthrough explains each step for manual use.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Azure ML Registry                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Environment   │  │ Deployment   │  │ Model        │  │
│  │ vllm-qwen35  │◄─│ Template     │◄─│ Qwen35-08B   │  │
│  │ (Dockerfile) │  │ vllm-1gpu-   │  │ (DT link)    │  │
│  │              │  │ h100         │  │              │  │
│  └──────────────┘  └──────┬───────┘  └──────────────┘  │
└─────────────────────┬─────┘──────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│  Azure ML Workspace                                     │
│  ┌──────────────┐  ┌──────────────┐                     │
│  │ Endpoint     │──│ Deployment   │                     │
│  │ qwen35-      │  │ qwen35-vllm  │                     │
│  │ endpoint     │  │ (references  │                     │
│  │              │  │  model→DT)   │                     │
│  └──────────────┘  └──────────────┘                     │
└─────────────────────────────────────────────────────────┘
```

The deployment template supplies: environment, scoring port (8000), health probes
(`/health`), env vars (vLLM config), and instance type. The deployment only needs
to reference the model — the DT provides everything else.

## Prerequisites

- Azure CLI with `ml` extension installed (`az extension add -n ml`)
- An Azure ML workspace and registry (see `scripts/cli/create-workspace.sh` / `create-registry.sh`)
- `az login` completed

~~~bash
# Set your variables (or edit configs/e2e-config.sh and source scripts/env.sh)
SUBSCRIPTION_ID="75703df0-38f9-4e2e-8328-45f6fc810286"
RESOURCE_GROUP="mabables-rg"
AZUREML_WORKSPACE="mabables-feb2026"
AZUREML_REGISTRY="mabables-reg-feb26"

MODEL_NAME="Qwen35-08B"
MODEL_VERSION="21"
HF_MODEL_ID="Qwen/Qwen3.5-0.8B"

ENVIRONMENT_NAME="vllm-qwen35"
ENVIRONMENT_VERSION="21"

TEMPLATE_NAME="vllm-1gpu-h100"
TEMPLATE_VERSION="21"

ENDPOINT_NAME="qwen35-endpoint"
DEPLOYMENT_NAME="qwen35-vllm"

az account set --subscription "$SUBSCRIPTION_ID"
~~~

## Step 1: Create the environment

The environment wraps vLLM in a Docker image with runit process supervision,
required by Azure ML managed endpoints.

Key design decisions:
- **Base image:** `vllm/vllm-openai:latest` — provides vLLM + CUDA + PyTorch
- **No nginx:** vLLM serves directly on port 8000 (the DT's `scoring_port`)
- **Strict offline:** `HF_HUB_OFFLINE=1` — no model downloads at runtime; model
  artifacts must be mounted via `model_mount_path`
- **`ENTRYPOINT []`:** Clears the base image entrypoint so `CMD ["runsvdir", "/var/runit"]`
  runs as the main process

Create in workspace first (builds the Docker image in the workspace ACR):

~~~bash
az ml environment create \
  --file scripts/cli/yaml/environment.yml \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP"
~~~

Wait for the image build to complete, then share to registry:

~~~bash
az ml environment share \
  --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
  --share-with-name "$ENVIRONMENT_NAME" --share-with-version "$ENVIRONMENT_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP"
~~~

> **Note:** The `az ml environment show --query image` field is always empty — the
> ARM API does not expose Docker build status. The automated script polls the Studio
> internal API to detect build completion. For manual use, check the workspace
> environment page in Azure ML Studio or wait ~5 minutes after `create` returns.

Verify:

~~~bash
az ml environment show \
  --name "$ENVIRONMENT_NAME" --version "$ENVIRONMENT_VERSION" \
  --registry-name "$AZUREML_REGISTRY" -o yaml
~~~

## Step 2: Create the deployment template

The deployment template defines everything the endpoint needs to serve the model:

| Field | Value | Why |
|-------|-------|-----|
| `scoring_port` | 8000 | vLLM's native HTTP port |
| `scoring_path` | `/v1` | OpenAI-compatible API root |
| `model_mount_path` | `/opt/ml/model` | Where Azure ML mounts model artifacts |
| `liveness_probe` | `/health:8000` | vLLM's health check endpoint |
| `environment_variables` | `VLLM_*`, `HF_HUB_OFFLINE` | Runtime config for vLLM |

~~~bash
az ml deployment-template create \
  --file scripts/cli/yaml/deployment-template.yml \
  --registry-name "$AZUREML_REGISTRY"
~~~

Verify:

~~~bash
az ml deployment-template show \
  --name "$TEMPLATE_NAME" --version "$TEMPLATE_VERSION" \
  --registry-name "$AZUREML_REGISTRY" -o yaml
~~~

## Step 3: Register the model

The model YAML includes two important fields:
- **`properties.aotManifest: "True"`** — required for the service to recognize model artifacts
- **`default_deployment_template`** — links model → DT so deployments auto-inherit settings

Download model artifacts from HuggingFace (skip if `model-artifacts/` already populated):

~~~bash
pip install huggingface_hub
python3 -c "
from huggingface_hub import snapshot_download
snapshot_download('$HF_MODEL_ID', local_dir='model-artifacts')
"
~~~

Register in registry (uploads ~1.77 GB — can take 20-30 minutes):

~~~bash
az ml model create \
  --file scripts/cli/yaml/model.yml \
  --registry-name "$AZUREML_REGISTRY"
~~~

Confirm the DT link:

~~~bash
az ml model show \
  --name "$MODEL_NAME" --version "$MODEL_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  --query "default_deployment_template.asset_id" -o tsv
# Expected: azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/21
~~~

## Step 4: Create the endpoint

~~~bash
az ml online-endpoint create \
  --file scripts/cli/yaml/endpoint.yml \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP"
~~~

## Step 5: Create the deployment

The deployment YAML is minimal — it only specifies the model reference, endpoint name,
and instance type. The deployment template (linked via the model) provides everything else:

~~~yaml
name: qwen35-vllm
endpoint_name: qwen35-endpoint
model: azureml://registries/mabables-reg-feb26/models/Qwen35-08B/versions/21
instance_type: Standard_NC40ads_H100_v5
instance_count: 1
~~~

> **Important:** Environment variables set in the deployment YAML are ignored when a
> deployment template is attached. Configure all env vars in the DT instead.

~~~bash
az ml online-deployment create \
  --file scripts/cli/yaml/deployment.yml \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  --all-traffic
~~~

The CLI will detect the DT linkage and print:

```
Model 'Qwen35-08B' (version 21) has a default deployment template configured.
The deployment will use the default deployment template settings.
Default deployment template: azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/21
```

Provisioning typically takes 15-30 minutes (H100 allocation + image pull + vLLM startup).

## Step 6: Test inference

~~~bash
SCORING_URI=$(az ml online-endpoint show \
  --name "$ENDPOINT_NAME" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  --query scoring_uri -o tsv)
BASE_URL="${SCORING_URI%/score}"

KEY=$(az ml online-endpoint get-credentials \
  --name "$ENDPOINT_NAME" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  --query primaryKey -o tsv)

curl -s "$BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.5-0.8B",
    "messages": [{"role": "user", "content": "Give me a short introduction to large language models."}],
    "max_tokens": 512
  }' | python3 -m json.tool
~~~

## File reference

| File | Purpose |
|------|---------|
| `configs/e2e-config.sh` | All version numbers and Azure resource names |
| `scripts/cli/yaml/Dockerfile` | vLLM + runit, strict offline mode |
| `scripts/cli/yaml/vllm-run.sh` | runit service script — translates DT env vars to vLLM CLI args |
| `scripts/cli/yaml/environment.yml` | Environment definition referencing the Dockerfile |
| `scripts/cli/yaml/deployment-template.yml` | DT: scoring port, probes, env vars, instance type |
| `scripts/cli/yaml/model.yml` | Model with `aotManifest` and `default_deployment_template` |
| `scripts/cli/yaml/endpoint.yml` | Online endpoint (key auth) |
| `scripts/cli/yaml/deployment.yml` | Minimal deployment — model + instance type only |
| `scripts/run-e2e-cli.sh` | Automated runner for all 6 steps with timing |

## Cleanup

~~~bash
# Delete deployment and endpoint
az ml online-endpoint delete --name "$ENDPOINT_NAME" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" --yes
~~~
