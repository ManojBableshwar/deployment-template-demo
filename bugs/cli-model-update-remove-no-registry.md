# Bug: `az ml model update --remove` does not support `--registry-name`

## Summary

The `az ml model update --remove` parameter requires `--resource-group` and
`--workspace-name` and does not accept `--registry-name`. This makes it
impossible to remove fields (such as `default_deployment_template`) from
**registry** models via the CLI.

This is especially impactful because removing the `defaultDeploymentTemplate`
field is the **only workaround** for the separate bug where changing an existing
DT in-place fails (see `dt-change-existing-fails-404.md`). Without CLI support
for `--remove` on registry models, users must fall back to direct REST API calls
to perform the workaround.

## Environment

- **Registry**: `mabables-reg-feb26` (eastus2)
- **CLI version**: `azure-cli 2.x` with `ml` extension
- **Date tested**: 2026-04-18

## Reproduction

### Step 1 — Verify `--remove` exists

```bash
az ml model update --help 2>&1 | grep -A2 "\-\-remove"
```

Output:

```
    --remove  : Remove a property or an element from a list.  Example:
                `--remove property.list <indexToRemove>` OR `--remove
                propertyToRemove`.
```

The `--remove` parameter is documented and available.

### Step 2 — Attempt `--remove` with `--registry-name`

```bash
az ml model update --name google--gemma-4-31b-it --version 1 \
  --registry-name mabables-reg-feb26 \
  --remove default_deployment_template
```

Error output:

```
the following arguments are required: --resource-group/-g

Examples from AI knowledge base:
az ml model update --name my-model --version 1 --set flavors.python_function.python_version=3.8 \
  --resource-group my-resource-group --workspace-name my-workspace
Update a model's flavors

https://aka.ms/cli_ref
Read more about the command in reference docs

Command exited with code 2
```

The CLI rejects the command and requires `--resource-group` — even though
`--registry-name` was provided as the scope.

### Step 3 — Verify `--set` works with `--registry-name` (for comparison)

```bash
az ml model update --name google--gemma-4-31b-it --version 1 \
  --registry-name mabables-reg-feb26 \
  --set default_deployment_template.asset_id="azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-google--gemma-4-31b-it/versions/1"
```

This **succeeds** (when setting the same value that's already set). So
`--registry-name` is a valid scope for `az ml model update --set`, but **not**
for `--remove`.

## Root cause analysis

The `az ml model update` command has two code paths in the CLI extension:

1. **`--set`**: Accepts both `--registry-name` and `--resource-group`/
   `--workspace-name` as scope parameters. Internally calls the MFE PUT API
   for registry models.
2. **`--remove`**: Only accepts `--resource-group`/`--workspace-name`. The
   argument parser does not register `--registry-name` as a valid scope for
   `--remove` operations, causing the CLI to reject the command before any
   API call is made.

This is a CLI argument validation gap — the underlying MFE API **does** support
removing fields from registry models (MFE PATCH with `op:"remove"` works), but
the CLI does not expose this capability.

## Workaround

Use the Model Registry PATCH API directly:

```bash
TOKEN=$(az account get-access-token --query accessToken -o tsv)

curl -sS -X PATCH \
  "https://eastus2.api.azureml.ms/modelregistry/v1.0/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.MachineLearningServices/registries/<registry>/models/<model-name>:<version>" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '[{"op":"remove","path":"/defaultDeploymentTemplate"}]'
```

This returns HTTP 202 and successfully removes the DT field from the registry
model.

### Constructing the URL

The Model Registry API URL requires the full resource path:

```
https://{region}.api.azureml.ms/modelregistry/v1.0/subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.MachineLearningServices/registries/{registry-name}/models/{model-name}:{version}
```

To find the subscription ID, resource group, and region for a registry:

```bash
az ml registry show --name <registry-name> --query "{subscription:id,location:location}" -o json
```

## Impact

### Direct impact

- Users cannot remove properties from registry models via `az ml` CLI
- Any workflow that requires clearing a field on a registry model (e.g.,
  `default_deployment_template`, `tags`, `properties`) must use direct REST
  API calls

### Compound impact with DT in-place change bug

Due to the separate bug where changing an existing DT fails
(`dt-change-existing-fails-404.md`), the only way to update a model's DT is
remove-then-add. Since the CLI doesn't support `--remove` for registries, the
**entire DT update workflow** is inaccessible via CLI:

1. `az ml model update --set` (single operation) → **fails** (DT in-place
   change bug)
2. `az ml model update --remove` then `--set` (two operations) → **fails**
   (`--remove` doesn't support `--registry-name`)
3. Direct MFE PATCH `op:"remove"` → `op:"add"` → **works** (but requires
   raw REST API calls)

This means there is **no CLI-only path** to update a deployment template on a
registry model.

### Affected operations

| CLI operation | `--workspace-name` | `--registry-name` |
|---------------|--------------------|--------------------|
| `az ml model update --set` | **Works** | **Works** |
| `az ml model update --remove` | **Works** | **Fails** — requires `-g` |
| `az ml model update --add` | Untested | Untested |

## Expected behavior

`az ml model update --remove` should accept `--registry-name` as a scope
parameter, consistent with `--set`:

```bash
# This should work
az ml model update --name google--gemma-4-31b-it --version 1 \
  --registry-name mabables-reg-feb26 \
  --remove default_deployment_template
```

The CLI should translate this into the appropriate MFE PATCH or PUT call to
remove the specified field from the registry model.
