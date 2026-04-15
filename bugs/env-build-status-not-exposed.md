# Bug: Environment API does not expose Docker image build status or image URI

**Date:** April 14, 2026  
**Reporter:** Manoj Bableshwar (mabables@microsoft.com)  
**Azure ML CLI version:** 2.41.1 (az 2.83.0)  
**ARM API version:** 2024-10-01  
**Region:** eastus2

---

## Summary

When creating an environment with a Dockerfile via `az ml environment create`, the Docker image build is triggered asynchronously. However, **neither the ARM REST API, the CLI, nor the Python SDK** expose the build status or the built image URI, making it impossible to programmatically determine when the build has completed.

The Azure ML Studio UI displays both fields (build status and ACR image URI), indicating the backend tracks this information but does not surface it through the public API.

This blocks automation workflows that need to `az ml environment share` the environment to a registry after creation, since sharing requires the image to be materialized in the workspace ACR first.

---

## Steps to Reproduce

### 1. Create environment with Dockerfile build

```bash
az ml environment create \
  --file environment.yml \
  --workspace-name mabables-feb2026 \
  --resource-group mabables-rg
```

Command returns successfully with the environment metadata, but the Docker image build is still in progress.

### 2. Query build status via CLI

```bash
az ml environment show \
  --name vllm-qwen35 --version 21 \
  --workspace-name mabables-feb2026 \
  --resource-group mabables-rg \
  --query "image" -o tsv
```

**Result:** Returns empty string, both during build AND after build completes.

The `image` field is never populated in the CLI output, even after the Azure ML Studio UI shows "Environment image build status: Succeeded" with a full ACR URI.

### 3. Attempt to share to registry immediately after create

```bash
az ml environment share \
  --name vllm-qwen35 --version 21 \
  --workspace-name mabables-feb2026 \
  --resource-group mabables-rg \
  --share-with-name vllm-qwen35 \
  --share-with-version 21 \
  --registry-name mabables-reg-feb26
```

**Result:** Fails with:

```
ERROR: (UserError) Environment with source assetId
azureml://locations/eastus2/workspaces/c4742136-9908-446e-b3b9-043f0033e4dc/environments/vllm-qwen35/versions/21
is not yet materialized in source ACR, please build the image before attempting
to publish it to destination mabables-reg-feb26.
```

---

## Observed Behavior

| Source | Build Status Visible? | Image URI Visible? |
|---|---|---|
| Studio internal API (`/environment/v1.0/.../image`) | Yes (`imageExistsInRegistry`) | Yes (`dockerImage.name` + `registry.address`) |
| ARM REST API (`2024-10-01`) | No | No |
| `az ml environment show` (CLI) | No | No (`image` field empty) |
| Python SDK `ml_client.environments.get()` | No | No |

### REST API response (after build completed successfully)

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "${WORKSPACE_BASE}/environments/vllm-qwen35/versions/21?api-version=2024-10-01"
```

```json
{
  "properties": {
    "environmentType": "UserCreated",
    "build": {
      "contextUri": "https://...blob.core.windows.net/.../yaml/",
      "dockerfilePath": "Dockerfile"
    },
    "osType": "Linux",
    "provisioningState": "Succeeded",
    "stage": "Development"
  }
}
```

**Note:** `provisioningState: "Succeeded"` refers to the environment *registration*, NOT the Docker image build. There is no `imageBuildStatus`, `image`, or `imageUri` field in the API response.

### How the Studio UI gets this data

The Studio UI does NOT use the ARM environment API. It calls a separate internal **environment image API**:

```
GET https://ml.azure.com/api/{region}/environment/v1.0/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.MachineLearningServices/workspaces/{workspace}/environments/{name}/versions/{version}/image?secrets=false
```

This returns the build status and image URI:

```json
{
  "imageExistsInRegistry": true,
  "dockerImage": {
    "name": "azureml/azureml_6b99146e1569faa7217bea74a5c795b1@sha256:f57570802282e972faf326716f8d8498677088392db486f763c0b01d0deb144c",
    "registry": {
      "address": "c47421369908446eb3b9043f0033e4dc.azurecr.io"
    }
  },
  "imageCapabilities": {
    "canAccessData": true,
    "hasCrossTenantSupport": false
  }
}
```

Key field: **`imageExistsInRegistry: true`** — this is the build completion indicator the Studio UI uses. When the build is in progress, this would be `false`.

This internal API is not documented, not available via CLI/SDK, and not part of the ARM resource provider contract. The ARM environment API should surface at minimum `imageExistsInRegistry` and `dockerImage` so that CLI/SDK users can poll for build completion without relying on undocumented internal endpoints.

---

## Expected Behavior

The ARM REST API response should include:

1. **`properties.imageBuildStatus`** — e.g., `Succeeded | Building | Failed`
2. **`properties.image`** — the full ACR URI once the build completes

The CLI and SDK should surface these fields accordingly.

This would allow:
```bash
# Poll for build completion via CLI
az ml environment show --name vllm-qwen35 --version 21 \
  --workspace-name mabables-feb2026 --resource-group mabables-rg \
  --query "build_status" -o tsv
# Returns: "Succeeded"

# Or via REST API
curl -s -H "Authorization: Bearer $TOKEN" \
  "${WORKSPACE_BASE}/environments/vllm-qwen35/versions/21?api-version=2024-10-01" \
  | jq '.properties.imageBuildStatus'
# Returns: "Succeeded"
```

---

## Impact

- **Automation blocked**: CI/CD pipelines that create environments and share to registries must use hardcoded `sleep` waits (we use 30 minutes) instead of polling for completion
- **No failure detection**: If the Docker build fails, the CLI/SDK user has no way to know — they must check the Studio UI manually
- **Workaround is fragile**: A fixed sleep may be too short (build fails silently) or too long (wastes CI time)

---

## Current Workaround

```bash
# Fixed 30-minute wait after environment create — no way to poll
info "Waiting 30 minutes for environment image build to complete…"
info "(Build status is not queryable via CLI/SDK — fixed wait required)"
sleep 1800

# Then attempt share
az ml environment share ...
```

---

## Environment Details

- **environment.yml:**
```yaml
$schema: https://azuremlschemas.azureedge.net/latest/environment.schema.json
name: vllm-qwen35
version: 21
build:
  path: .
  dockerfile_path: Dockerfile
```

- **Dockerfile:** `FROM vllm/vllm-openai:latest` (base image ~8 GB, build takes 15-30 min)
