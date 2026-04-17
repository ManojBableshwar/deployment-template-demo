# Bug: Deployment template fields not applied to deployment

## Summary

When creating a deployment that references a deployment template (DT), **most
DT fields are not applied** to the resulting deployment. The ARM API shows `null`
or default values for environment, environment variables, probes, model mount
path, and request settings — only `instanceType` and `instanceCount` are applied.

## Field-by-field comparison

DT values (from `az ml deployment-template show`) vs actual deployment (from ARM
API `GET .../deployments/qwen35-vllm?api-version=2025-04-01-preview`):

| DT field | DT value | Deployment value | Applied? |
|----------|----------|------------------|----------|
| `environmentId` | `azureml://registries/.../vllm-qwen35/versions/50` | `null` | **No** |
| `environmentVariables` | 8 env vars (HF_HOME, VLLM_MAX_NUM_SEQS, etc.) | `null` | **No** |
| `modelMountPath` | `/opt/ml/model` | `null` | **No** |
| `livenessProbe` | GET /health:8000, initialDelay PT10M, period PT10S | `null` | **No** |
| `readinessProbe` | GET /health:8000, initialDelay PT10M, period PT10S | `null` | **No** |
| `requestSettings.maxConcurrentRequestsPerInstance` | `250` | `0` | **No** |
| `requestSettings.requestTimeout` | `PT1M30S` (90s) | `PT0S` | **No** |
| `scoringPort` | `8000` | _(not in ARM response)_ | Unknown |
| `scoringPath` | `/v1` | _(not in ARM response)_ | Unknown |
| `instanceType` | `Standard_NC24ads_A100_v4` (in allowedInstanceTypes) | `Standard_NC24ads_A100_v4` | **Yes** |
| `instanceCount` | `1` | `1` (sku.capacity) | **Yes** |

## Expected behavior

All DT fields should be applied to the deployment at creation time. The
deployment should inherit environment, env vars, probes, request settings,
model mount path, scoring port/path from the DT.

## Actual behavior

Only `instanceType` and `instanceCount` are applied. Everything else is `null`
or defaults. The deployment works because these values are apparently applied
server-side at runtime but **not reflected in the ARM resource representation**.

This means:
- `az ml online-deployment show` returns incomplete data
- There is no way to verify that DT settings were applied
- Monitoring / auditing tools see null probes and zero timeouts
- It is impossible to tell whether a value was intentionally set to null by the
  user or was inherited from the DT

## Evidence

### DT stored correctly (Step 2)

```json
{
  "environmentId": "azureml://registries/mabables-reg-feb26/environments/vllm-qwen35/versions/50",
  "environmentVariables": {
    "HF_HOME": "/tmp/hf_cache",
    "HF_HUB_OFFLINE": "1",
    "TRANSFORMERS_OFFLINE": "1",
    "VLLM_GPU_MEMORY_UTILIZATION": "0.9",
    "VLLM_MAX_MODEL_LEN": "131072",
    "VLLM_MAX_NUM_SEQS": "48",
    "VLLM_NO_USAGE_STATS": "1",
    "VLLM_TENSOR_PARALLEL_SIZE": "1"
  },
  "livenessProbe": {
    "httpMethod": "GET",
    "initialDelay": "PT10M",
    "path": "/health",
    "period": "PT10S",
    "port": 8000,
    "scheme": "http",
    "successThreshold": 1,
    "timeout": "PT10S"
  },
  "readinessProbe": { "..." },
  "requestSettings": {
    "maxConcurrentRequestsPerInstance": 250,
    "requestTimeout": "PT1M30S"
  },
  "modelMountPath": "/opt/ml/model",
  "scoringPath": "/v1",
  "scoringPort": 8000
}
```

### Deployment ARM response (Step 5) — fields missing

```json
{
  "properties": {
    "environmentId": null,
    "environmentVariables": null,
    "modelMountPath": null,
    "livenessProbe": null,
    "readinessProbe": null,
    "startupProbe": null,
    "requestSettings": {
      "maxQueueWait": "PT0S",
      "requestTimeout": "PT0S",
      "maxConcurrentRequestsPerInstance": 0
    },
    "instanceType": "Standard_NC24ads_A100_v4",
    "model": "azureml://registries/mabables-reg-feb26/models/Qwen35-08B/versions/50"
  },
  "sku": {
    "capacity": 1
  }
}
```

## Reproduction

```bash
# 1. Create DT with all fields
az ml deployment-template create \
  --file scripts/cli/yaml/deployment-template.yml \
  --registry-name "$AZUREML_REGISTRY"

# 2. Create deployment referencing DT via model's default_deployment_template
az ml online-deployment create \
  --file scripts/cli/yaml/deployment-a100.yml \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP"

# 3. Check deployment via ARM API — most fields are null
TOKEN=$(az account get-access-token --query accessToken -o tsv)
curl -sS -H "Authorization: Bearer $TOKEN" \
  "${WORKSPACE_BASE}/onlineEndpoints/qwen35-ep-a100/deployments/qwen35-vllm?api-version=2025-04-01-preview" \
  | python3 -m json.tool
```

## Open question

The deployment **does work** — vLLM starts with the correct environment, env
vars, probes, and scoring path. So these values are likely applied server-side
at runtime via the DT reference. The bug may be that the ARM resource
representation doesn't merge/reflect DT values, rather than them not being
applied at all. Either way, the deployment API response is misleading.
