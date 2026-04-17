# Bug: `AZUREML_MODEL_DIR` not set in deployment container

## Summary

When Azure ML creates a deployment using a deployment template (DT) with
`modelMountPath: /opt/ml/model`, the container's `AZUREML_MODEL_DIR` environment
variable is **not set**. The deployment works only because our `vllm-run.sh`
entrypoint hardcodes the same path as a fallback:

```bash
BASE="${AZUREML_MODEL_DIR:-/opt/ml/model}"
```

This is **working by coincidence**, not by design.

## Expected behavior

Azure ML should set `AZUREML_MODEL_DIR=/opt/ml/model` (or whatever
`modelMountPath` is configured in the DT) as an environment variable inside
the container, just like it does for standard (non-DT) managed online
deployments where `AZUREML_MODEL_DIR` is always set.

## Actual behavior

- The ARM API shows `environmentVariables: null` on the deployment (no env vars
  inherited from the DT — see [dt-request-settings-not-applied.md](dt-request-settings-not-applied.md))
- The ARM API shows `modelMountPath: null` on the deployment  
- The container's `AZUREML_MODEL_DIR` env var is not set (confirmed by
  `vllm-run.sh` diagnostics: `AZUREML_MODEL_DIR=<not set>`)
- The model **is** mounted at `/opt/ml/model` — Azure ML does honor the DT's
  `modelMountPath` for the actual mount, but does not expose it as an env var

## Evidence

### DT configuration

```json
{
  "modelMountPath": "/opt/ml/model",
  "environmentVariables": {
    "HF_HOME": "/tmp/hf_cache",
    "VLLM_MAX_NUM_SEQS": "48",
    ...
  }
}
```

### Deployment ARM response

```json
{
  "properties": {
    "environmentVariables": null,
    "modelMountPath": null
  }
}
```

### vllm-run.sh startup diagnostics

```
===== vLLM startup diagnostics =====
AZUREML_MODEL_DIR=<not set>
model_mount_path (DT default)=/opt/ml/model
Resolved BASE=/opt/ml/model
✓ /opt/ml/model exists (directory)
```

The script falls back to `/opt/ml/model` because `AZUREML_MODEL_DIR` is empty.

### vllm-run.sh fallback code

```bash
# Fall back to /opt/ml/model if AZUREML_MODEL_DIR is not set
BASE="${AZUREML_MODEL_DIR:-/opt/ml/model}"
```

Without this hardcoded fallback, the deployment would fail.

## Why this matters

1. **Fragile by design:** The only reason the deployment works is that the
   entrypoint script author happens to know the DT's `modelMountPath` and
   hardcoded it as a fallback. If someone changes `modelMountPath` in the DT
   without updating the entrypoint, the deployment breaks silently.

2. **Non-portable entrypoints:** Standard Azure ML deployments (without DTs)
   always set `AZUREML_MODEL_DIR`. Entrypoint scripts written for standard
   deployments (using `$AZUREML_MODEL_DIR`) will fail when used with DTs
   unless they add model-path-specific fallbacks.

3. **DT env vars not injected:** The DT sets 8 env vars
   (`VLLM_MAX_NUM_SEQS`, `VLLM_GPU_MEMORY_UTILIZATION`, etc.) but the
   deployment shows `environmentVariables: null`. The `vllm-run.sh` script
   uses these env vars — if they are not injected, vLLM would fall back to
   its own defaults (e.g., `max_num_seqs=256` instead of the DT's `48`).
   The deployment works, which suggests these **are** injected at runtime
   but not reflected in the ARM API.

4. **Impossible to debug remotely:** Since the ARM API shows `null` for
   both `environmentVariables` and `modelMountPath`, there is no way to
   verify from outside the container what values are actually in effect.

## Proposed fix

Azure ML should:

1. Set `AZUREML_MODEL_DIR` to the DT's `modelMountPath` value in the
   container environment (just like standard deployments do)
2. Reflect all DT-inherited fields in the deployment's ARM resource
   representation so they can be audited via API/CLI

## Related

- [dt-request-settings-not-applied.md](dt-request-settings-not-applied.md) —
  broader issue of DT fields not reflected in deployment ARM response
