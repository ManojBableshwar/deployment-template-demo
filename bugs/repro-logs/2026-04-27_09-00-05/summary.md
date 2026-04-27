# DT Change Bug — Repro Results

**Date**: 2026-04-27 16:00:05 UTC
**Registry**: mabables-reg-feb26 (eastus2)
**Subscription**: 75703df0-38f9-4e2e-8328-45f6fc810286
**Model**: google--gemma-4-31b-it v1
**DT name**: vllm-google--gemma-4-31b-it

## Prerequisite checks
- [x] `deployment-template show --name vllm-google--gemma-4-31b-it --version 1` — exists
- [x] `deployment-template show --name vllm-google--gemma-4-31b-it --version 2` — exists
- [x] `deployment-template show --name vllm-google--gemma-4-31b-it --version 3` — exists
- [x] `environment show --name vllm-server --version 1` — exists
- [x] `environment show --name vllm-server --version 2` — exists
- [x] `model show --name google--gemma-4-31b-it --version 1` — exists

**CLI version**: 2.83.0 / ml ext 2.42.0

## Test results

| # | Method | From DT | To DT | Result | HTTP/Exit | Correlation ID | Notes |
|---|--------|---------|-------|--------|-----------|----------------|-------|
| 1 | CLI `model update --set` | v1 | v1 (same) | ✅ PASS | exit=0 | `(see debug log)` | Idempotent re-set (baseline) |
| 2 | CLI `model update --set` | v1 | v3 | ✅ PASS | exit=0 | `(see debug log)` | **BUG** — change existing DT via CLI |
| 3 | MFE PATCH `add` | (none) | v2 | ✅ PASS | 202 | `573d9c52-639c-4612-832b-7b467fe85de9` | Add to empty field (baseline) |
| 4 | MFE PATCH `add` | v2 | v3 | ✅ PASS | 202 | `96e833e8-9848-4215-9a43-786baaf9356b` | **BUG** — change existing DT via PATCH add |
| 5 | MFE PATCH `replace` | v2 | v1 | ✅ PASS | 202 | `5101e7e1-0533-41e9-98e6-7183697ef5fd` | **BUG** — change existing DT via PATCH replace |
| 6 | MFE PATCH `remove` | v2 | (none) | ✅ PASS | 202 | `8e9f0055-5ad7-4768-a674-52f37dac2606` | Remove works (baseline) |
| 7 | Workaround `remove`+`add` | v1 | v2 | ✅ PASS | 202/202 | `dcf8a994-f733-43fa-a1ad-04f2e4c577f8 / 100fdefb-2681-455f-896a-ad70f6d5a46e` | Two-step workaround succeeds |

## Summary

- **Total tests**: 7
- **Passed**: 7
- **Failed**: 0 (tests 2, 4, 5 — all demonstrate the bug)

**Pattern**: Any operation that *changes* an existing DT to a different version fails.
Operations that set the same value, add to an empty field, remove, or use the two-step
workaround (remove → add) all succeed.

## Failed request details (for service-side correlation)

### test2

- **Correlation ID**: `(see debug log)`

Response body:
```json
{
    "creation_context": {
        "created_at": "2026-04-18T22:30:02.061766+00:00",
        "created_by": "Manoj Bableshwar",
        "created_by_type": "User",
        "last_modified_at": "2026-04-27T16:01:59.037261+00:00",
        "last_modified_by": "Manoj Bableshwar",
        "last_modified_by_type": "User"
    },
    "default_deployment_template": {
        "asset_id": "azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-google--gemma-4-31b-it/versions/3"
    },
    "description": "google--gemma-4-31b-it with deployment template v1  -- azcopy upload",
    "id": "azureml://registries/mabables-reg-feb26/models/google--gemma-4-31b-it/versions/1",
    "name": "google--gemma-4-31b-it",
    "path": "https://6ec5159fc0c.blob.core.windows.net/mabables-r-c0297896-e148-53ce-99fc-86ee0d15760b",
    "properties": {
        "modelManifestPathOrUri": "/mabables-r-891b3cb4-b277-5dcc-ae5b-dfefc6816208/manifest.base.json"
    },
    "tags": {
        "framework": "transformers",
        "hf_model_id": "google/gemma-4-31B-it",
        "source": "huggingface"
    },
    "type": "custom_model",
    "version": "1"
}
```

CLI error (from `--debug` log):
```
    "code": "UserError",
```

### test4

- **Correlation ID**: `96e833e8-9848-4215-9a43-786baaf9356b`
- **HTTP status**: 202

Response headers:
```
HTTP/2 202 
date: Mon, 27 Apr 2026 16:02:47 GMT
content-type: application/json; charset=utf-8
content-length: 148
location: https://eastus2.api.azureml.ms/assetstore/v1.0/operations/768nNr622ds9FQRPMftt4bXcBsH3hf13PHUqMKk5hW4
request-context: appId=cid-v1:2d2e8e63-272e-4b3c-8598-4ee570a0e70d
x-ms-response-type: standard
mise-correlation-id: 96e833e8-9848-4215-9a43-786baaf9356b
strict-transport-security: max-age=31536000; includeSubDomains; preload
x-content-type-options: nosniff
azureml-served-by-cluster: vienna-eastus2-02
x-request-time: 0.657

```

Response body:
```json
{
    "location": "https://eastus2.api.azureml.ms/assetstore/v1.0/operations/768nNr622ds9FQRPMftt4bXcBsH3hf13PHUqMKk5hW4",
    "operationResult": null
}
```

### test5

- **Correlation ID**: `5101e7e1-0533-41e9-98e6-7183697ef5fd`
- **HTTP status**: 202

Response headers:
```
HTTP/2 202 
date: Mon, 27 Apr 2026 16:02:55 GMT
content-type: application/json; charset=utf-8
content-length: 148
location: https://eastus2.api.azureml.ms/assetstore/v1.0/operations/lbbbXZeAyy5OUNYOaALX-IkPDPcrOlAGoY4iwxVMa-s
request-context: appId=cid-v1:2d2e8e63-272e-4b3c-8598-4ee570a0e70d
x-ms-response-type: standard
mise-correlation-id: 5101e7e1-0533-41e9-98e6-7183697ef5fd
strict-transport-security: max-age=31536000; includeSubDomains; preload
x-content-type-options: nosniff
azureml-served-by-cluster: vienna-eastus2-02
x-request-time: 0.752

```

Response body:
```json
{
    "location": "https://eastus2.api.azureml.ms/assetstore/v1.0/operations/lbbbXZeAyy5OUNYOaALX-IkPDPcrOlAGoY4iwxVMa-s",
    "operationResult": null
}
```


## Log files

All files in: `/Users/mabables/CODE/REPOS/deployment-template-demo/bugs/repro-logs/2026-04-27_09-00-05/`

| File | Description |
|------|-------------|
| `run.log` | Timestamped execution log |
| `summary.md` | This summary |
| `test*-request.json` | Request payloads sent |
| `test*-response-body.json` | Response bodies |
| `test*-response-headers.txt` | Full HTTP response headers (includes x-ms-request-id) |
| `test*-debug.log` | CLI --debug output (tests 1-2) |

## Environment

```
{
  "environmentName": "AzureCloud",
  "homeTenantId": "7f292395-a08f-4cc0-b3d0-a400b023b0d2",
  "id": "75703df0-38f9-4e2e-8328-45f6fc810286",
  "isDefault": true,
  "managedByTenants": [],
  "name": "Azure subscription 1",
  "state": "Enabled",
  "tenantId": "7f292395-a08f-4cc0-b3d0-a400b023b0d2",
  "user": {
    "name": "mabables@microsoft.com",
    "type": "user"
  }
}
```
