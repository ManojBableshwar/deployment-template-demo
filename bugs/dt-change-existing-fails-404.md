# Bug: Changing an existing defaultDeploymentTemplate on a model fails with 404

## Summary

When a model in a **registry** already has a `defaultDeploymentTemplate` (DT)
set, attempting to change it to a different DT version fails with a 404 error.
The failure occurs on **all API surfaces** that support DT patching — both
`az ml model update --set` (which issues a full PUT to MFE) and the Model
Registry PATCH API (`op:"add"` and `op:"replace"`). Re-setting the **same** DT
value succeeds. Setting a DT on a model with **no** DT set also succeeds.

The only workaround is a two-step operation via direct API: first `op:"remove"`
the DT field, then `op:"add"` the new DT.

## Environment

- **Registry**: `mabables-reg-feb26` (eastus2)
- **Subscription**: `75703df0-38f9-4e2e-8328-45f6fc810286`
- **Resource group**: `mabables-rg`
- **CLI version**: `az ml` extension `2.x` (ml extension)
- **Date tested**: 2026-04-18

## Assets used in testing

| Asset | Version | Notes |
|-------|---------|-------|
| Model `google--gemma-4-31b-it` | v1 | Initially has DT v1 |
| Model `google--gemma-4-31b-it` | v2 | Initially has DT v2 |
| DT `vllm-google--gemma-4-31b-it` | v1 | References env `vllm-server` v1 |
| DT `vllm-google--gemma-4-31b-it` | v2 | References env `vllm-server` v2 |
| DT `vllm-google--gemma-4-31b-it` | v3 | References env `vllm-server` v2 |
| Environment `vllm-server` | v1 | Dockerfile-based, exists and accessible |
| Environment `vllm-server` | v2 | Dockerfile-based, exists and accessible |

All assets verified accessible independently:

```bash
# All return successfully
az ml deployment-template show --name vllm-google--gemma-4-31b-it --version 1 --registry-name mabables-reg-feb26
az ml deployment-template show --name vllm-google--gemma-4-31b-it --version 2 --registry-name mabables-reg-feb26
az ml deployment-template show --name vllm-google--gemma-4-31b-it --version 3 --registry-name mabables-reg-feb26
az ml environment show --name vllm-server --version 1 --registry-name mabables-reg-feb26
az ml environment show --name vllm-server --version 2 --registry-name mabables-reg-feb26
```

## Reproduction

### Test matrix (complete results)

| # | Method | From DT | To DT | Result | Error |
|---|--------|---------|-------|--------|-------|
| 1 | `az ml model update --set` | v1 | v1 (same) | **OK** | — |
| 2 | `az ml model update --set` | v1 | v3 | **FAIL** | `Invalid containerUri` |
| 3 | MFE PATCH `op:"add"` | (none) | v2 | **OK** | — |
| 4 | MFE PATCH `op:"add"` | v2 | v3 | **FAIL** | 404 `Could not find environment` |
| 5 | MFE PATCH `op:"replace"` | v2 | v1 | **FAIL** | 404 `Could not find environment` |
| 6 | MFE PATCH `op:"remove"` | v2 | (none) | **OK** | — |
| 7 | MFE PATCH `op:"remove"` → `op:"add"` | v1 | v2 | **OK** | — |

**Pattern**: Any operation that **changes** an existing DT to a different value
fails. Operations that set the same value, add to an empty field, or remove the
field all succeed.

### Test 2 — CLI failure (`az ml model update --set`)

Starting state: model v1 has DT v1.

```bash
az ml model update --name google--gemma-4-31b-it --version 1 \
  --registry-name mabables-reg-feb26 \
  --set default_deployment_template.asset_id="azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-google--gemma-4-31b-it/versions/3"
```

Error output:

```
ERROR: (UserError) Invalid containerUri https://6ec5159fc0c.blob.core.windows.net/mabables-r-<uuid>/...
Code: UserError
Message: Invalid containerUri https://6ec5159fc0c.blob.core.windows.net/mabables-r-<uuid>/...
```

The `containerUri` in the error refers to the **model's** blob storage container
(not the environment's). The model data has not changed — only the DT reference
is being updated. The CLI internally does a full GET → modify → PUT to MFE,
which triggers a revalidation of the model's blob container that fails in this
context.

### Test 4 — MFE PATCH failure (`op:"add"`, changing existing DT)

Starting state: model v1 has DT v2 (set in test 3).

```bash
TOKEN=$(az account get-access-token --query accessToken -o tsv)

curl -sS -X PATCH \
  "https://eastus2.api.azureml.ms/modelregistry/v1.0/subscriptions/75703df0-fbeb-4893-a1bb-cd2e0e5a04c4/resourceGroups/mabables-rg/providers/Microsoft.MachineLearningServices/registries/mabables-reg-feb26/models/google--gemma-4-31b-it:1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{
    "op": "add",
    "path": "/defaultDeploymentTemplate",
    "value": {
      "assetId": "azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-google--gemma-4-31b-it/versions/3"
    }
  }]'
```

Response (HTTP 404):

```json
{
  "error": {
    "code": "UserError",
    "message": "Could not find asset with ID: azureml://registries/mabables-reg-feb26/environments/vllm-server/versions/2"
  }
}
```

Note the error references `vllm-server/versions/2` — this is the environment
referenced by the **current** DT (v2), NOT the target DT (v3). The environment
exists and is accessible via `az ml environment show`.

### Test 5 — MFE PATCH failure (`op:"replace"`)

Starting state: model v1 has DT v2.

```bash
curl -sS -X PATCH \
  "https://eastus2.api.azureml.ms/modelregistry/v1.0/.../models/google--gemma-4-31b-it:1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{
    "op": "replace",
    "path": "/defaultDeploymentTemplate",
    "value": {
      "assetId": "azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-google--gemma-4-31b-it/versions/1"
    }
  }]'
```

Response (HTTP 404):

```json
{
  "error": {
    "code": "UserError",
    "message": "Could not find asset with ID: azureml://registries/mabables-reg-feb26/environments/vllm-server/versions/1"
  }
}
```

Same class of error. Here the 404 references `vllm-server/versions/1` — the
environment of the **target** DT (v1). Both `add` and `replace` fail, but the
environment version referenced in the error can vary.

### Test 7 — Workaround (remove + add)

Starting state: model v1 has DT v1.

```bash
TOKEN=$(az account get-access-token --query accessToken -o tsv)
MODEL_URL="https://eastus2.api.azureml.ms/modelregistry/v1.0/subscriptions/75703df0-fbeb-4893-a1bb-cd2e0e5a04c4/resourceGroups/mabables-rg/providers/Microsoft.MachineLearningServices/registries/mabables-reg-feb26/models/google--gemma-4-31b-it:1"

# Step 1: Remove existing DT
curl -sS -X PATCH "$MODEL_URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{"op":"remove","path":"/defaultDeploymentTemplate"}]'
# → HTTP 202 OK

# Verify removal
az ml model show --name google--gemma-4-31b-it --version 1 \
  --registry-name mabables-reg-feb26 \
  --query "default_deployment_template" -o json
# → {}

# Step 2: Add new DT
curl -sS -X PATCH "$MODEL_URL" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{
    "op": "add",
    "path": "/defaultDeploymentTemplate",
    "value": {
      "assetId": "azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-google--gemma-4-31b-it/versions/2"
    }
  }]'
# → HTTP 202 OK

# Verify
az ml model show --name google--gemma-4-31b-it --version 1 \
  --registry-name mabables-reg-feb26 \
  --query "default_deployment_template" -o json
# → {"asset_id": "azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-google--gemma-4-31b-it/versions/2"}
```

This was tested multiple times with different DT version combinations — it works
consistently.

## Root cause analysis

The bug is in MFE's model update code path for `defaultDeploymentTemplate`:

1. When MFE receives a request to **change** a DT (not removal, not same-value
   idempotent re-set), it attempts to resolve the DT's referenced environment
   as part of the update validation
2. This environment resolution step fails with a 404, even though the
   environment exists in the registry and is independently accessible
3. When the DT field is **empty** (after removal) or **unchanged** (idempotent
   re-set), the environment resolution step is either skipped or takes a
   different code path, so the operation succeeds

The error message referencing the environment (not the DT itself) indicates
that MFE internally dereferences the DT → resolves its `environmentId` →
attempts to validate the environment — and this validation fails specifically
in the "replace existing DT" flow.

### What this is NOT caused by

- **Cross-region replication / blob storage lag**: Both the current and target
  environments exist in the same region (`eastus2`) in the same registry. They
  are directly accessible via `az ml environment show`.
- **Environment not existing**: Verified via both CLI and direct API calls.
  All environment versions used in DTs exist and are accessible.
- **Model blob container issues**: The model's blob data is unchanged during a
  DT-only update. The `Invalid containerUri` error from the CLI path is a
  secondary symptom of the same underlying issue.
- **Permissions**: The same identity can successfully remove and add the DT in
  two steps but cannot change it in one step.

## Impact

- **Self-serve model publishing**: The script `7-patch-model-default-dt.sh`
  (which sets a model's default DT after registration) cannot update a model's
  DT if one is already set — it must first remove and re-add
- **Model lifecycle management**: Models published to a registry with an initial
  DT cannot have their DT updated to a newer version in a single operation
- **DT versioning workflow**: The natural workflow of "create DT v2, update
  model to point to DT v2" is broken — requires a fragile two-step workaround
  with a window where the model has no DT set
- **Automation fragility**: The remove-then-add workaround introduces a race
  condition — if the second call fails, the model is left with no DT

## API surface coverage

| API | DT field supported? | In-place change works? |
|-----|---------------------|------------------------|
| MFE Dataplane PUT (CLI uses) | Yes | **No** — `Invalid containerUri` |
| Model Registry PATCH (`op:"add"`) | Yes | **No** — 404 environment not found |
| Model Registry PATCH (`op:"replace"`) | Yes | **No** — 404 environment not found |
| Model Registry PATCH (`op:"remove"` → `op:"add"`) | Yes | **Yes** (workaround) |
| ARM PUT (`management.azure.com`) | **No** — field not in schema | N/A |

## Expected behavior

All of these should succeed for changing a DT:

```bash
# CLI
az ml model update --name <model> --version <ver> --registry-name <reg> \
  --set default_deployment_template.asset_id="azureml://registries/<reg>/deploymentTemplates/<dt>/versions/<new>"

# MFE PATCH add
curl -X PATCH "$URL" -d '[{"op":"add","path":"/defaultDeploymentTemplate","value":{"assetId":"..."}}]'

# MFE PATCH replace
curl -X PATCH "$URL" -d '[{"op":"replace","path":"/defaultDeploymentTemplate","value":{"assetId":"..."}}]'
```

The update should apply the new DT reference without re-validating unrelated
blob containers or failing to resolve environments that exist.
