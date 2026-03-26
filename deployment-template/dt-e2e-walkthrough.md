# Deployment Template E2E Walkthrough (Direct CLI Commands)

This walkthrough mirrors the BYOC format, but for Deployment Templates, using direct Azure CLI commands only.
It covers both:
- A full historical CLI run from available logs
- The current custom-registry failure path that reproduces the service bug

## Prerequisites

~~~bash
cd /Users/mabables/CODE/REPOS/deployment-template-demo
source .venv/bin/activate

SUBSCRIPTION_ID="75703df0-38f9-4e2e-8328-45f6fc810286"
RESOURCE_GROUP="mabables-rg"
AZUREML_WORKSPACE="mabables-feb2026"
AZUREML_REGISTRY="mabables-reg-feb26"

MODEL_NAME="Qwen35-08B"
MODEL_VERSION="13"
HF_MODEL_ID="Qwen/Qwen3.5-0.8B"

ENVIRONMENT_NAME="vllm-qwen35"
ENVIRONMENT_VERSION="11"

TEMPLATE_NAME="vllm-1gpu-h100"
TEMPLATE_VERSION="6"

ENDPOINT_NAME="qwen35-endpoint"
DEPLOYMENT_NAME="qwen35-vllm"

az account set --subscription "$SUBSCRIPTION_ID"
~~~

## 1. Identify the model

Goal:
- Use Qwen3.5-0.8B and register a model asset that links to a deployment template.

Model intro command:

~~~bash
az ml model show \
  --name "$MODEL_NAME" \
  --version "$MODEL_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -o yaml
~~~

Output snippet (from deployment-template/dt-issue.md):

~~~yaml
name: Qwen35-08B
version: '13'
default_deployment_template:
  asset_id: azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/6
~~~

## 2. Identify the runtime (why vLLM)

Goal:
- Use an OpenAI-compatible runtime suitable for transformer chat serving on GPU.

Runtime is defined by the deployment template environment reference:

~~~bash
az ml deployment-template show \
  --name "$TEMPLATE_NAME" \
  --version "$TEMPLATE_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -o json
~~~

Output snippet (from logs/cli/2026-03-25_02-24-19/2-create-deployment-template.log):

~~~json
{
  "name": "vllm-1gpu-h100",
  "deploymentTemplateType": "managedOnline",
  "environmentId": "azureml://registries/mabables-reg-feb26/environments/vllm-qwen35/versions/11"
}
~~~

## 3. Wrap vLLM with Dockerfile and create environment

Why wrap:
- Azure ML managed online endpoints require runit supervision and health probing on port 5001.
- The custom Dockerfile adds runit + nginx and runs vLLM behind nginx.

Create environment in workspace from Dockerfile YAML:

~~~bash
az ml environment create \
  --file deployment-template/scripts/cli/yaml/environment.yml \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP"
~~~

Share environment to registry version used by DT:

~~~bash
az ml environment share \
  --name "$ENVIRONMENT_NAME" \
  --version "$ENVIRONMENT_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  --share-with-name "$ENVIRONMENT_NAME" \
  --share-with-version "$ENVIRONMENT_VERSION" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP"
~~~

Output snippet (from byoc/logs/1-environment.log, same env asset):

~~~yaml
id: azureml://registries/mabables-reg-feb26/environments/vllm-qwen35/versions/11
name: vllm-qwen35
version: '11'
~~~

## 4. Download and register model

Download model artifacts locally (example):

~~~bash
python - <<'PY'
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id="Qwen/Qwen3.5-0.8B",
    local_dir="model-artifacts",
    local_dir_use_symlinks=False,
)
print("Downloaded to model-artifacts/")
PY
~~~

Register model with deployment-template link:

~~~bash
az ml model create \
  --file deployment-template/scripts/cli/yaml/model.yml \
  --registry-name "$AZUREML_REGISTRY"
~~~

Confirm DT link:

~~~bash
az ml model show \
  --name "$MODEL_NAME" \
  --version "$MODEL_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  --query "default_deployment_template.asset_id" -o tsv
~~~

## 5. Create endpoint

~~~bash
az ml online-endpoint create \
  --file deployment-template/scripts/cli/yaml/endpoint.yml \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP"
~~~

Output snippet (from logs/cli/2026-03-25_02-24-19/4-create-online-endpoint.log):

~~~json
{
  "name": "qwen35-endpoint",
  "provisioning_state": "Succeeded"
}
~~~

## 6. Create deployment

~~~bash
az ml online-deployment create \
  --file deployment-template/scripts/cli/yaml/deployment.yml \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  --all-traffic
~~~

Current expected result in custom-registry DT scenario:

~~~json
{
  "error": {
    "code": "ModelRegistryError",
    "message": "Could not find asset with ID: azureml://registries/mabables-reg-feb26/environments/vllm-qwen35/versions/11"
  },
  "status": "Failed"
}
~~~

## 7. Test deployment

If step 6 succeeds in your environment, test inference directly with CLI-derived endpoint URL + key.

~~~bash
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
        "max_tokens": 50
      }'
~~~

Historical success snippet (from logs/cli/2026-03-25_02-24-19/6-test-inference.log):

~~~json
{
  "model": "Qwen3.5-0.8B",
  "choices": [
    {
      "finish_reason": "stop"
    }
  ]
}
~~~

## Sources used for snippets

- logs/cli/2026-03-25_02-24-19/2-create-deployment-template.log
- logs/cli/2026-03-25_02-24-19/4-create-online-endpoint.log
- logs/cli/2026-03-25_02-24-19/6-test-inference.log
- byoc/logs/1-environment.log
- deployment-template/dt-issue.md
