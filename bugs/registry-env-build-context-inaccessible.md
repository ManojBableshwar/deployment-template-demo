# Bug: Registry environment build context blobs are inaccessible to clients due to DenyAssignment

**Date:** April 17, 2026
**Reporter:** Manoj Bableshwar (mabables@microsoft.com)
**Azure ML CLI version:** 2.41.1 (az 2.83.0)
**ARM API version:** 2024-10-01
**Region:** eastus2

---

## Summary

When an Azure ML environment is created in a **workspace**, the build context (Dockerfile, scripts, etc.) is stored in the workspace's default blob storage account. Users with workspace access can download these files using `az storage blob download --auth-mode key` because the CLI can auto-discover the storage account key via ARM `listKeys`.

When the same environment is promoted to a **registry** (via `az ml environment share`), the build context is copied to the **registry's managed storage account**. This storage account lives in a system-managed resource group where Azure ML applies a **DenyAssignment** (`Azure Machine Learning Services User RG access Denier`), blocking all user-initiated `listKeys` calls — even for users with Owner/Contributor roles on the subscription.

This means **clients cannot programmatically download the Dockerfile or other build context files for registry environments**, even though the ARM API returns the blob storage URL in `build.path`. The Azure ML Studio UI can display these files because it calls an internal `getBlobReferenceSAS` data-plane API that generates SAS tokens via the service's own privileged identity.

---

## Registry vs. Workspace: Key Differences

### Storage architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  WORKSPACE environment                                          │
│                                                                 │
│  Storage account: mabablesfeb2028493783618                       │
│  Resource group:  mabables-rg  (user-managed)                   │
│  Container:       azureml-blobstore-{workspace-id}              │
│                                                                 │
│  User access: ✅ listKeys works → az storage blob download OK   │
│  ARM build.path:  https://mabablesfeb2028493783618.blob.core... │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  REGISTRY environment                                           │
│                                                                 │
│  Storage account: 6ec5159fc0c                                   │
│  Resource group:  azureml-rg-mabables-reg-feb26_{guid}          │
│                   (system-managed, DenyAssignment applied)       │
│  Container:       mabables-r-{guid}                             │
│                                                                 │
│  User access: ❌ listKeys blocked by DenyAssignment             │
│  ARM build.path:  https://6ec5159fc0c.blob.core.windows.net/... │
│                                                                 │
│  Studio UI:   ✅ Uses internal getBlobReferenceSAS API           │
│               (backend calls with service identity)             │
└─────────────────────────────────────────────────────────────────┘
```

### Access comparison

| Operation | Workspace env | Registry env |
|-----------|--------------|--------------|
| `az ml environment show --query "build"` | ✅ Returns `build.path` (blob URL) | ✅ Returns `build.path` (blob URL) |
| `az storage blob list --auth-mode key` | ✅ CLI auto-discovers key via `listKeys` | ❌ `DenyAssignmentAuthorizationFailed` |
| `az storage blob list --auth-mode login` | ❌ Requires `Storage Blob Data Reader` RBAC | ❌ DenyAssignment blocks data-plane too |
| `az storage blob download` | ✅ Works with `--auth-mode key` | ❌ Blocked |
| Studio UI → Context tab | ✅ Uses `getBlobReferenceSAS` | ✅ Uses `getBlobReferenceSAS` |

### Why this happens

Azure ML registries create a **system-managed resource group** (`azureml-rg-{registry}_{guid}`) containing the registry's storage account, ACR, and other infrastructure. To prevent users from accidentally breaking registry internals, Azure ML applies a **DenyAssignment** on this resource group:

```
Deny assignment: Azure Machine Learning Services User RG access Denier
ID:              11dcc6242c1a4e9dbb93516449382d1a
Scope:           /subscriptions/{sub}/resourceGroups/azureml-rg-{registry}_{guid}
```

This blocks `Microsoft.Storage/storageAccounts/listKeys/action` for all user principals, while allowing the Azure ML service's own managed identity to access storage. The Studio UI's `getBlobReferenceSAS` API works because it runs server-side with the service identity.

---

## Steps to Reproduce

### 1. Get the build context URL from ARM API

```bash
az ml environment show \
  --name vllm-qwen35 --version 50 \
  --registry-name mabables-reg-feb26 \
  --query "build" -o json
```

**Output:**
```json
{
  "dockerfile_path": "Dockerfile",
  "path": "https://6ec5159fc0c.blob.core.windows.net/mabables-r-b9e12eea-9763-5fd2-b7fc-9fd564b1e8f2/LocalUpload/a3d7d29829871dfea3553ae69c1738795d87c2bf639bf84c4fd0e42065344e45/yaml"
}
```

### 2. Attempt to list/download files from this blob path

```bash
az storage blob list \
  --account-name 6ec5159fc0c \
  --container-name "mabables-r-b9e12eea-9763-5fd2-b7fc-9fd564b1e8f2" \
  --prefix "LocalUpload/a3d7d29829871dfea3553ae69c1738795d87c2bf639bf84c4fd0e42065344e45/yaml/" \
  --auth-mode key -o table
```

**Error:**
```
DenyAssignmentAuthorizationFailed: The client 'mabables@microsoft.com' with
object id 'b0a38401-...' has permission to perform action
'Microsoft.Storage/storageAccounts/listKeys/action' on scope
'/subscriptions/.../resourceGroups/azureml-rg-mabables-reg-feb26_.../providers/
Microsoft.Storage/storageAccounts/6ec5159fc0c'; however, the access is denied
because of the deny assignment with name 'Azure Machine Learning Services User
RG access Denier' and Id '11dcc6242c1a4e9dbb93516449382d1a' at scope
'/subscriptions/.../resourceGroups/azureml-rg-mabables-reg-feb26_...'.
```

### 3. Attempt with storage data-plane token (AAD)

```bash
STORAGE_TOKEN=$(az account get-access-token --resource https://storage.azure.com/ --query accessToken -o tsv)
curl -s -H "Authorization: Bearer $STORAGE_TOKEN" -H "x-ms-version: 2020-10-02" \
  "https://6ec5159fc0c.blob.core.windows.net/mabables-r-.../LocalUpload/.../yaml/Dockerfile"
```

**Error:**
```xml
<Error>
  <Code>AuthorizationPermissionMismatch</Code>
  <Message>This request is not authorized to perform this operation using this permission.</Message>
</Error>
```

### 4. Contrast: Workspace environment works fine

```bash
# Same files, workspace storage — works
az storage blob list \
  --account-name mabablesfeb2028493783618 \
  --container-name "azureml-blobstore-c4742136-9908-446e-b3b9-043f0033e4dc" \
  --prefix "LocalUpload/.../yaml/" \
  --auth-mode key -o table
```

**Output:**
```
Name                                                      Blob Type    Length
--------------------------------------------------------  -----------  ------
LocalUpload/.../yaml/Dockerfile                           BlockBlob    612
LocalUpload/.../yaml/deployment-template.yml              BlockBlob    1163
LocalUpload/.../yaml/deployment.yml                       BlockBlob    576
LocalUpload/.../yaml/endpoint.yml                         BlockBlob    188
LocalUpload/.../yaml/environment.yml                      BlockBlob    299
LocalUpload/.../yaml/model.json                           BlockBlob
LocalUpload/.../yaml/model.yml                            BlockBlob    533
LocalUpload/.../yaml/vllm-run.sh                          BlockBlob    2529
```

```bash
az storage blob download \
  --account-name mabablesfeb2028493783618 \
  --container-name "azureml-blobstore-..." \
  --name "LocalUpload/.../yaml/Dockerfile" \
  --auth-mode key --file /tmp/Dockerfile && cat /tmp/Dockerfile
```

**Output:**
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

---

## How the Studio UI Gets These Files

The Studio UI's "Context" tab calls three internal APIs in sequence:

### 1. `metadata` — gets the build context location
```
GET https://ml.azure.com/api/eastus2/environment/v1.0/.../environments/{name}/versions/{version}/metadata
```
Returns `docker.buildContext.location` (blob URL) and `dockerfilePath`.

### 2. `getBlobReferenceSAS` — generates SAS token for each file
```
POST https://ml.azure.com/api/eastus2/...getBlobReferenceSAS
```
The Studio backend generates SAS tokens using the **service's own managed identity**, bypassing the DenyAssignment.

### 3. Blob download via SAS URL
The browser downloads each file using the SAS URL returned in step 2.

None of these APIs are documented or available via CLI/SDK.

---

## Expected Behavior

Users who have access to a registry environment should be able to download its build context files. Options:

### Option A: Public `getBlobReferenceSAS` API
Expose the Studio's internal `getBlobReferenceSAS` as a documented ARM or data-plane API:
```bash
az ml environment download-build-context \
  --name vllm-qwen35 --version 50 \
  --registry-name mabables-reg-feb26 \
  --download-path ./build-context/
```

### Option B: Include build context content in ARM API response
Return the Dockerfile content inline in the environment properties (it's typically small):
```json
{
  "properties": {
    "build": {
      "contextUri": "...",
      "dockerfilePath": "Dockerfile",
      "dockerfileContent": "FROM vllm/vllm-openai:latest\n..."
    }
  }
}
```

### Option C: Grant `Storage Blob Data Reader` via registry RBAC
When a user has `AzureML Registry Reader` role, automatically grant them `Storage Blob Data Reader` on the registry's managed storage (or a scoped read-only SAS).

---

## Impact

- **Cannot inspect registry environment Dockerfile:** Partners and model publishers who consume registry environments cannot view the Dockerfile or entrypoint scripts to understand what's running in the container
- **Cannot audit registry environments:** Security teams cannot programmatically retrieve the Dockerfile for compliance review or vulnerability assessment
- **Cannot debug deployment failures:** When a deployment using a registry environment fails, operators cannot inspect the build context to diagnose container issues
- **Workspace-to-registry asymmetry:** The same environment is fully inspectable in the workspace but opaque after promotion to registry — this is confusing and undermines the registry as a sharing mechanism

---

## Related Bugs

- **[env-image-api-not-exposed.md](env-image-api-not-exposed.md):** ARM API missing `imageBuildStatus`, `builtImage`, and ACR address fields — a schema gap in the ARM API. This bug is about **access control** (DenyAssignment) preventing access to data that the ARM API already exposes a URL for.
