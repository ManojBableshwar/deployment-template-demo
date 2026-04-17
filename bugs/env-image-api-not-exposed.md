# Bug: Environment ARM API does not expose Docker image build status, built image URI, or ACR address

**Date:** April 14, 2026 (updated April 17, 2026)
**Reporter:** Manoj Bableshwar (mabables@microsoft.com)
**Azure ML CLI version:** 2.41.1 (az 2.83.0)
**ARM API versions tested:** 2024-10-01, 2025-04-01-preview, 2025-12-01
**Region:** eastus2

---

## Summary

When creating an environment with a Dockerfile via `az ml environment create`, the Docker image build is triggered asynchronously. After build completion, the built image is pushed to the workspace or registry ACR. However, **neither the ARM REST API, the CLI, nor the Python SDK** expose:

1. **Build status** — impossible to programmatically determine when the build has completed (or failed)
2. **Built image URI** — the full ACR image reference (e.g. `{hash}.azurecr.io/.../azureml_{hash}`) is never returned
3. **ACR address** — the registry login server where the image was pushed

The Azure ML Studio UI displays all three by calling a **separate internal data-plane API** (`/environment/v1.0/.../image`). This API is not documented, not available via CLI/SDK, and not part of the ARM resource provider contract.

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

### 2. Query build status via CLI (during or after build)

```bash
az ml environment show \
  --name vllm-qwen35 --version 50 \
  --workspace-name mabables-feb2026 \
  --resource-group mabables-rg \
  --query "image" -o tsv
```

**Result:** Returns empty string, both during build AND after build completes.

The `image` field is never populated in the CLI output, even after the Azure ML Studio UI shows "Environment image build status: Succeeded" with a full ACR URI.

### 3. Attempt to share to registry immediately after create

```bash
az ml environment share \
  --name vllm-qwen35 --version 50 \
  --workspace-name mabables-feb2026 \
  --resource-group mabables-rg \
  --share-with-name vllm-qwen35 \
  --share-with-version 50 \
  --registry-name mabables-reg-feb26
```

**Result:** Fails if image build is still in progress:

```
ERROR: (UserError) Environment with source assetId
azureml://locations/eastus2/workspaces/c4742136-9908-446e-b3b9-043f0033e4dc/environments/vllm-qwen35/versions/50
is not yet materialized in source ACR, please build the image before attempting
to publish it to destination mabables-reg-feb26.
```

### 4. Query via CLI after successful build

```bash
az ml environment show \
  --name vllm-qwen35 --version 50 \
  --registry-name mabables-reg-feb26 \
  -o json
```

**CLI output (abbreviated):**

```json
{
  "build": {
    "dockerfile_path": "Dockerfile",
    "path": "https://6ec5159fc0c.blob.core.windows.net/.../yaml"
  },
  "description": "vLLM OpenAI-compatible inference server with runit for Azure ML managed endpoints",
  "id": "azureml://registries/mabables-reg-feb26/environments/vllm-qwen35/versions/50",
  "name": "vllm-qwen35",
  "os_type": "linux",
  "version": "50"
}
```

**Missing:** No ACR address, no built Docker image URI, no image digest, no build status.

### 5. Query via ARM REST API after successful build

```bash
TOKEN=$(az account get-access-token --query accessToken -o tsv)

# Workspace environment
curl -s -H "Authorization: Bearer $TOKEN" \
  "${WORKSPACE_BASE}/environments/vllm-qwen35/versions/50?api-version=2025-12-01"

# Registry environment
curl -s -H "Authorization: Bearer $TOKEN" \
  "${REGISTRY_BASE}/environments/vllm-qwen35/versions/50?api-version=2025-12-01"
```

**ARM API response `properties` (abbreviated):**

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

**Note:** `provisioningState: "Succeeded"` refers to the environment *registration*, NOT the Docker image build. There is no `imageBuildStatus`, `builtImage`, or `imageUri` field in the response.

---

## Observed Behavior

| Source | Build Status? | Built Image URI? | ACR Address? |
|---|---|---|---|
| Studio internal API (`/environment/v1.0/.../image`) | Yes (`imageExistsInRegistry`) | Yes (`dockerImage.name`) | Yes (`dockerImage.registry.address`) |
| ARM REST API (all versions) | No | No | No |
| `az ml environment show` (CLI) | No | No (`image` field empty) | No |
| Python SDK `ml_client.environments.get()` | No | No | No |

---

## How the Studio UI Gets This Data

The Studio UI does NOT use the ARM environment API. It calls a separate internal **environment image API** (data-plane, not ARM):

```
GET https://ml.azure.com/api/{region}/environment/v1.0/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.MachineLearningServices/workspaces/{workspace}/environments/{name}/versions/{version}/image?secrets=false
```

**Headers:**
```
Authorization: Bearer {same-AAD-token}
```

**Response:**

```json
{
  "imageExistsInRegistry": true,
  "intellectualPropertyPublisher": null,
  "imageCapabilities": {
    "canAccessData": true,
    "hasCrossTenantSupport": false
  },
  "ingredients": null,
  "vulnerabilityFindings": {
    "details": null
  },
  "pythonEnvironment": {
    "interpreterPath": "python",
    "condaEnvironmentName": null,
    "condaEnvironmentPath": null
  },
  "dockerImage": {
    "name": "3b25b39762c.azurecr.io/mabables-reg-feb26/2fae9e00-8f31-5032-b2ff-0f52e11fb645/vllm-qwen35/azureml/azureml_d892741a6e44601ebbb1f43441a6b0b9",
    "registry": {
      "address": "3b25b39762c.azurecr.io",
      "username": null,
      "password": null
    }
  },
  "warnings": []
}
```

### Key observations about this internal API

1. **Not ARM:** The base URL is `ml.azure.com/api/{region}/environment/v1.0/...` — this is a data-plane endpoint, not managed through Azure Resource Manager
2. **Not documented:** No public docs, no OpenAPI spec, no CLI/SDK wrapper
3. **Same auth:** Uses the same AAD bearer token as the ARM API, so no additional permissions are needed
4. **Two endpoints available:**
   - **Workspace-scoped:** `GET .../workspaces/{workspace}/environments/{name}/versions/{version}/image?secrets=false` — requires workspace context
   - **Registry-scoped:** `POST .../consume/imageDetails` with body `{"assetId":"azureml://registries/{reg}/environments/{name}/versions/{version}"}` — takes the registry asset ID directly, no workspace needed
5. **Contains fields the ARM API should have:**
   - `imageExistsInRegistry` — build completion indicator (`true`/`false`)
   - `dockerImage.name` — full ACR image URI (with org, namespace, image name)
   - `dockerImage.registry.address` — the ACR login server
   - `imageCapabilities` — data access and cross-tenant support flags
   - `pythonEnvironment` — interpreter path, conda env info
   - `vulnerabilityFindings` — security scan results

---

## ARM API Schema Analysis

The [Environment Versions - Get](https://learn.microsoft.com/en-us/rest/api/azureml/environment-versions/get) (API version 2025-12-01) defines `EnvironmentVersionProperties` with:

| Field | Type | Description | Populated for Dockerfile builds? |
|-------|------|-------------|----------------------------------|
| `image` | `string` | "Name of the image that will be used for the environment" | **No** — this is the *input* base image (e.g. `docker.io/tensorflow/serving:latest`), only populated when `image:` is used instead of `build:` |
| `build` | `BuildContext` | Docker build context URI + Dockerfile path | Yes — but only the *input* build context, not the *output* built image |
| `provisioningState` | `AssetProvisioningState` | Provisioning state | Yes — but this is the *registration* state, not the image *build* state |

There is **no field** in the ARM schema for:
- The built/output Docker image URI or digest
- The ACR registry address
- The image build status (separate from asset provisioning)
- Image capabilities or vulnerability findings

The same gap applies to [Registry Environment Versions - Get](https://learn.microsoft.com/en-us/rest/api/azureml/registry-environment-versions/get).

---

## Expected Behavior

The ARM REST API response should include build status and built image metadata:

```json
{
  "properties": {
    "environmentType": "UserCreated",
    "build": {
      "contextUri": "https://...blob.core.windows.net/.../yaml/",
      "dockerfilePath": "Dockerfile"
    },
    "imageBuildStatus": "Succeeded",
    "builtImage": {
      "name": "3b25b39762c.azurecr.io/mabables-reg-feb26/.../vllm-qwen35/azureml/azureml_d892741a6e44601ebbb1f43441a6b0b9",
      "digest": "sha256:f57570802282e972faf326716f8d8498677088392db486f763c0b01d0deb144c",
      "registry": {
        "address": "3b25b39762c.azurecr.io"
      }
    },
    "imageCapabilities": {
      "canAccessData": true,
      "hasCrossTenantSupport": false
    },
    "osType": "Linux",
    "provisioningState": "Succeeded",
    "stage": "Development"
  }
}
```

The CLI and SDK should surface these fields:

```bash
# Poll for build completion
az ml environment show --name vllm-qwen35 --version 50 \
  --workspace-name mabables-feb2026 --resource-group mabables-rg \
  --query "image_build_status" -o tsv
# Expected: "Succeeded"

# Get the built ACR image URI
az ml environment show --name vllm-qwen35 --version 50 \
  --registry-name mabables-reg-feb26 \
  --query "built_image.name" -o tsv
# Expected: 3b25b39762c.azurecr.io/.../azureml_d892741a6e44601ebbb1f43441a6b0b9

# Get the ACR address
az ml environment show --name vllm-qwen35 --version 50 \
  --registry-name mabables-reg-feb26 \
  --query "built_image.registry.address" -o tsv
# Expected: 3b25b39762c.azurecr.io
```

---

## Impact

### Build status not exposed
- **Automation blocked:** CI/CD pipelines that create environments and share to registries cannot poll for build completion — forced to use fixed `sleep` waits
- **No failure detection:** If the Docker build fails, CLI/SDK users have no way to know — they must check the Studio UI manually
- **Workaround is fragile:** A fixed sleep may be too short (build fails silently) or too long (wastes CI time)

### Built image URI / ACR address not exposed
- **No programmatic access to built image URI:** Automation workflows that need the ACR image (e.g. for vulnerability scanning, image promotion, debugging container pull failures) must parse Studio UI network calls or hardcode/guess the ACR naming convention
- **ACR naming convention is opaque:** The built image path (`{hash}.azurecr.io/{registry}/{guid}/{env-name}/azureml/azureml_{hash}`) is not documented and not discoverable without the internal API
- **Debugging deployment failures:** When a deployment fails to pull the environment image, operators need the actual ACR URI to diagnose ACR access, network, or image issues — currently only available via the Studio UI
- **Security/compliance:** Organizations that require image scanning or attestation cannot programmatically retrieve the image reference to feed into their scanning pipeline

---

## Current Workaround

### Polling for build completion

Our script polls the internal environment image API for `imageExistsInRegistry`:

```bash
ENV_IMAGE_API="https://ml.azure.com/api/${REGION}/environment/v1.0/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.MachineLearningServices/workspaces/${WS}/environments/${ENV_NAME}/versions/${ENV_VERSION}/image?secrets=false"
TOKEN=$(az account get-access-token --query accessToken -o tsv)

# Poll every 30s until imageExistsInRegistry == True (up to 1 hour)
while true; do
  IMAGE_EXISTS=$(curl -s -H "Authorization: Bearer $TOKEN" "$ENV_IMAGE_API" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('imageExistsInRegistry',''))")
  [[ "$IMAGE_EXISTS" == "True" ]] && break
  sleep 30
done
```

### Retrieving ACR image URI

```bash
curl -s -H "Authorization: Bearer $TOKEN" "$ENV_IMAGE_API" | python3 -m json.tool
```

Both workarounds are fragile because:
1. The API is undocumented and may change without notice
2. It requires workspace context even for registry environments
3. The URL structure (`ml.azure.com/api/{region}/...`) is a Studio frontend pattern, not a stable service endpoint

---

## Proposed Fix

Add three new fields to `EnvironmentVersionProperties` in the ARM schema:

| New field | Type | Description |
|-----------|------|-------------|
| `imageBuildStatus` | `string` enum | `Building`, `Succeeded`, `Failed` — the Docker image build state (distinct from `provisioningState`) |
| `builtImage` | `object` | `{ name, digest, registry: { address } }` — the output ACR image after a successful build |
| `imageCapabilities` | `object` | `{ canAccessData, hasCrossTenantSupport }` — image capability flags |

This would eliminate the need for the undocumented internal API for all three use cases: build polling, image URI retrieval, and capability introspection.

---

## Environment Details

- **environment.yml:**
```yaml
$schema: https://azuremlschemas.azureedge.net/latest/environment.schema.json
name: vllm-qwen35
version: 50
build:
  path: .
  dockerfile_path: Dockerfile
```

- **Dockerfile:**
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

- **Base image:** `vllm/vllm-openai:latest` (~8 GB, build takes 15–30 min)
