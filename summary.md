# Deployment Template Bug Report — Support Ticket Evidence

**Date:** March 26, 2026  
**Reporter:** Manoj Bableshwar (mabables@microsoft.com)  
**Azure ML CLI version:** 2.41.1 (az 2.83.0)  
**Python SDK version:** azure-ai-ml 1.32.0  
**Region:** eastus2

---

## Executive Summary

Deploying a model with `defaultDeploymentTemplate` on an Azure ML managed online
endpoint **always fails** with `ModelPresetNotFound` when the deployment template
references an environment in a **custom registry** (i.e., not the official
`azureml` catalog).

The identical model, environment, and endpoint **succeed** when deployed directly
(BYOC — Bring Your Own Container) without a deployment template, proving the
issue is in the server-side `CreatePresetDeploymentFlow`.

---

## Environment

| Resource | Value |
|---|---|
| Subscription | `75703df0-38f9-4e2e-8328-45f6fc810286` |
| Resource Group | `mabables-rg` |
| Workspace | `mabables-feb2026` (eastus2) |
| Registry | `mabables-reg-feb26` (eastus2) |
| Model | `Qwen35-08B` (Qwen/Qwen3.5-0.8B, 1.77 GB) |
| Environment | `vllm-qwen35` v11 (Dockerfile: vLLM + runit + nginx) |
| Deployment Template | `vllm-1gpu-h100` v6 |
| SKU | `Standard_NC40ads_H100_v5` |
| Endpoint | `qwen35-endpoint` |

---

## What Works: BYOC (No Deployment Template)

**Result: ✅ SUCCESS** — Full logs in `byoc/logs/`

Using the same environment (v11) and same model artifacts (v5) but **without** a
deployment template, the deployment succeeds and inference works.

### Steps executed:
1. **Environment** — `vllm-qwen35` v11 exists in registry `mabables-reg-feb26`
   (Dockerfile-based: `FROM vllm/vllm-openai:latest` + runit + nginx)
2. **Model** — `Qwen35-08B` v5 registered in registry (1.77 GB, `default_deployment_template: {}`)
3. **Endpoint** — `qwen35-endpoint` created in workspace
4. **Deployment** — `byoc-vllm` created with explicit environment, probes, and
   env vars in the deployment YAML (no DT reference)
5. **Inference** — Chat completions working via curl and OpenAI SDK

### Deployment YAML (BYOC — works):
```yaml
name: byoc-vllm
endpoint_name: qwen35-endpoint
model: azureml://registries/mabables-reg-feb26/models/Qwen35-08B/versions/5
environment: azureml://registries/mabables-reg-feb26/environments/vllm-qwen35/versions/11
instance_type: Standard_NC40ads_H100_v5
instance_count: 1
environment_variables:
  VLLM_SERVED_MODEL_NAME: "Qwen3.5-0.8B"
  VLLM_MODEL_NAME: "/opt/ml/model"
  VLLM_TENSOR_PARALLEL_SIZE: "1"
  VLLM_MAX_MODEL_LEN: "131072"
  VLLM_GPU_MEMORY_UTILIZATION: "0.9"
  HF_HOME: "/tmp/hf_cache"
```

### Inference proof (curl):
```
$ curl -s "$BASE_URL/v1/chat/completions" -H "Authorization: Bearer $KEY" \
  -d '{"model":"Qwen3.5-0.8B","messages":[{"role":"user","content":"Say hello in 5 words"}],"max_tokens":50}'

{
  "id": "chatcmpl-...",
  "model": "Qwen3.5-0.8B",
  "choices": [{
    "message": {"role": "assistant", "content": "Hello! How can I help?"},
    "finish_reason": "stop"
  }]
}
```

### Inference proof (OpenAI SDK):
```python
from openai import OpenAI
client = OpenAI(base_url=f"{endpoint_url}/v1", api_key=key)
response = client.chat.completions.create(
    model="Qwen3.5-0.8B",
    messages=[{"role": "user", "content": "Give me a short introduction to large language models."}],
    max_tokens=256,
)
# Returns successful completion with 111 tokens
```

---

## What Fails: Deployment Template

**Result: ❌ FAILS** — `ModelPresetNotFound` every time

Using the same environment (v11) but with a deployment template (v6) linked to the
model (v13), the deployment **always fails immediately** (~5 seconds) with a 404 from
`ModelRegistryClient.GetModelDeploymentSettingsAsync`.

### Asset chain:
```
Model v13  →  DT v6  →  Environment v11
  (defaultDeploymentTemplate.asset_id =
   azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/6)
```

### Deployment YAML (DT — fails):
```yaml
name: qwen35-vllm
endpoint_name: qwen35-endpoint
model: azureml://registries/mabables-reg-feb26/models/Qwen35-08B/versions/13
instance_type: Standard_NC40ads_H100_v5
instance_count: 1
environment_variables:
  VLLM_SERVED_MODEL_NAME: "Qwen3.5-0.8B"
```

### CLI command:
```bash
az ml online-deployment create \
  --file deployment.yml \
  -w mabables-feb2026 -g mabables-rg --all-traffic
```

### Error (from async operation status):
```json
{
  "error": {
    "code": "ModelRegistryError",
    "message": "Could not find asset with ID: azureml://registries/mabables-reg-feb26/environments/vllm-qwen35/versions/11"
  },
  "status": "Failed",
  "startTime": "2026-03-26T01:00:34.148Z",
  "endTime": "2026-03-26T01:00:39.833Z"
}
```

### Full stack trace (from mfeOperationsStatus):
```
ModelRegistryClient.GetModelDeploymentSettingsAsync
  → ModelRegistryModelPresetsProvider.FetchAsync
  → MultiSourceModelPresetsProvider.FetchAsync
  → CreatePresetDeploymentFlow.ExecuteTurnAsync

Error: "Failed to get model deployment settings. Status code: NotFound.
Error details: <NotFoundError> Could not find asset with ID:
azureml://registries/mabables-reg-feb26/environments/vllm-qwen35/versions/11"

ErrorType: ModelPresetNotFound
```

---

## Root Cause Analysis

The server-side `CreatePresetDeploymentFlow` is triggered whenever a model has
a non-empty `defaultDeploymentTemplate`. This flow calls
`ModelRegistryClient.GetModelDeploymentSettingsAsync`, which internally resolves
the environment referenced by the deployment template.

**The bug:** `ModelRegistryClient` cannot resolve environments from custom
registries (e.g., `mabables-reg-feb26`). It appears to only support environments
from the official Azure ML catalog registry (`azureml`). When it encounters an
environment ID like `azureml://registries/mabables-reg-feb26/environments/...`,
it returns a 404 `NotFoundError`.

### Evidence:
1. The environment **exists** — `az ml environment show --name vllm-qwen35 --version 11 --registry-name mabables-reg-feb26` succeeds
2. The environment **works in deployments** — the BYOC deployment uses it successfully
3. The DT **exists** — `az ml deployment-template show --name vllm-1gpu-h100 --version 6 --registry-name mabables-reg-feb26` succeeds
4. The model **exists with DT link** — `az ml model show --name Qwen35-08B --version 13 --registry-name mabables-reg-feb26` shows `default_deployment_template.asset_id` pointing to DT v6
5. The failure happens **server-side in < 6 seconds** — not a timeout, image build, or container issue
6. Tried with **multiple environment versions** (v8, v10, v11) — all fail with the same error
7. Tried via **CLI and REST API** — same result

### Versions tried:

| Model | DT | Environment | Result |
|---|---|---|---|
| v11 | v4 | v8 (pre-built image) | ❌ ModelPresetNotFound |
| v12 | v5 | v10 (pre-built image, promoted) | ❌ ModelPresetNotFound |
| v13 | v6 | v11 (Dockerfile, promoted) | ❌ ModelPresetNotFound |
| v5 | (none) | v11 (explicit in YAML) | ✅ Success (BYOC) |

---

## Reproduction Steps

### Prerequisites
- Azure ML CLI v2.41.1+ with `deployment-template` preview extension
- Azure ML registry with a custom environment
- Model registered with `defaultDeploymentTemplate` pointing to a DT in the same registry

### Steps
1. Create environment in custom registry:
   ```bash
   az ml environment share --name vllm-qwen35 --version 9 \
     --registry-name mabables-reg-feb26 \
     --share-with-name vllm-qwen35 --share-with-version 11 \
     -w mabables-feb2026 -g mabables-rg
   ```

2. Create deployment template in registry:
   ```bash
   az ml deployment-template create \
     --file deployment-template.yml \
     --registry-name mabables-reg-feb26
   ```

3. Register model with DT reference:
   ```bash
   az ml model create \
     --file model.yml \
     --registry-name mabables-reg-feb26
   ```
   Where `model.yml` includes:
   ```yaml
   default_deployment_template:
     asset_id: azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/6
   ```

4. Deploy:
   ```bash
   az ml online-deployment create \
     --file deployment.yml \
     -w mabables-feb2026 -g mabables-rg
   ```

5. **Observe immediate failure** with `ModelPresetNotFound`.

---

## Expected Behavior

When a model has `defaultDeploymentTemplate` pointing to a deployment template
in the **same custom registry**, and that DT references an environment in the
same registry, the deployment should:
1. Read the DT settings from the registry
2. Resolve the environment from the registry
3. Apply DT settings (environment, probes, env vars, scoring config) to the deployment
4. Proceed with normal deployment provisioning

---

## Actual Behavior

The `CreatePresetDeploymentFlow` fires, calls `ModelRegistryClient.GetModelDeploymentSettingsAsync`,
which fails with a 404 because it cannot find environments in custom registries.
The deployment fails in < 6 seconds without any image building or container provisioning.

---

## Workaround

Deploy without using deployment templates (BYOC): specify all configuration
(environment, probes, env vars, scoring config) explicitly in the deployment YAML.
This works perfectly with the same environment and model artifacts.

See the `byoc/` folder for a complete working example.

---

## Files in This Repository

```
deployment-template-demo/
├── summary.md                          ← This file
├── deployment-template/                ← DT-based flow (FAILS)
│   ├── configs/e2e-config.sh
│   ├── docs/deployment-templates-intro.md
│   └── scripts/
│       ├── cli/                        ← CLI + YAML snippets
│       │   ├── 1-create-environment.sh
│       │   ├── 2-create-deployment-template.sh
│       │   ├── 3-register-model.sh
│       │   ├── 4-create-online-endpoint.sh
│       │   ├── 5-create-online-deployment.sh
│       │   ├── 6-test-inference.sh
│       │   └── yaml/
│       │       ├── Dockerfile
│       │       ├── environment.yml
│       │       ├── deployment-template.yml
│       │       ├── model.yml           ← Has defaultDeploymentTemplate
│       │       ├── deployment.yml      ← Minimal (DT provides settings)
│       │       └── endpoint.yml
│       ├── sdk/                        ← Python SDK snippets
│       │   ├── 1_create_environment.py
│       │   ├── 2_create_deployment_template.py
│       │   ├── 3_register_model.py
│       │   ├── 4_create_online_endpoint.py
│       │   ├── 5_create_online_deployment.py
│       │   └── 6_test_inference.py
│       ├── api/                        ← REST API snippets
│       │   ├── 1-create-environment.sh
│       │   ├── 2-create-deployment-template.sh
│       │   ├── 3-register-model.sh
│       │   ├── 4-create-online-endpoint.sh
│       │   ├── 5-create-online-deployment.sh
│       │   └── 6-test-inference.sh
│       └── rest_deploy.py              ← REST API deploy (also fails)
├── byoc/                               ← BYOC flow (WORKS)
│   ├── config.sh
│   ├── yaml/
│   │   ├── Dockerfile
│   │   ├── environment.yml
│   │   ├── model.yml                   ← No defaultDeploymentTemplate
│   │   ├── deployment.yml              ← All settings explicit
│   │   └── endpoint.yml
│   ├── scripts/
│   │   ├── run-e2e.sh                  ← Full E2E runner
│   │   └── test_openai_sdk.py
│   └── logs/                           ← Complete E2E execution logs
│       ├── e2e-run.log                 ← Full run log
│       ├── 1-environment.log
│       ├── 2-model.log
│       ├── 3-endpoint.log
│       ├── 4-deployment.log            ← Deployment succeeded
│       ├── 5-inference.log             ← curl tests passed
│       └── 6-openai-sdk.log            ← OpenAI SDK tests passed
└── model-artifacts/                    ← Qwen3.5-0.8B weights (gitignored)
```
