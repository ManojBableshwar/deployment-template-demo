# DT Change Bug — Repro Results

**Date**: 2026-04-21 16:05:21 UTC
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
| 2 | CLI `model update --set` | v1 | v3 | ❌ FAIL | exit=1 | `(see debug log)` | **BUG** — change existing DT via CLI |
| 3 | MFE PATCH `add` | (none) | v2 | ✅ PASS | 202 | `de75a6a5-73d9-4ccd-8b4a-56860197748f` | Add to empty field (baseline) |
| 4 | MFE PATCH `add` | v2 | v3 | ❌ FAIL | 404 | `00ce5131-659b-4a3f-92b1-0b9b4354da72` | **BUG** — change existing DT via PATCH add |
| 5 | MFE PATCH `replace` | v2 | v1 | ❌ FAIL | 404 | `f270f6de-81cd-412a-98d5-d1c42e6e23f7` | **BUG** — change existing DT via PATCH replace |
| 6 | MFE PATCH `remove` | v2 | (none) | ✅ PASS | 202 | `6afd8d11-730f-4b64-926c-e7d9f774fb98` | Remove works (baseline) |
| 7 | Workaround `remove`+`add` | v1 | v2 | ✅ PASS | 202/202 | `e9f386f5-a192-4fbc-8a8b-75312a68e6ea / b06340a3-3d6a-4cb1-916b-e6f89c52f505` | Two-step workaround succeeds |

## Summary

- **Total tests**: 7
- **Passed**: 4
- **Failed**: 3 (tests 2, 4, 5 — all demonstrate the bug)

**Pattern**: Any operation that *changes* an existing DT to a different version fails.
Operations that set the same value, add to an empty field, remove, or use the two-step
workaround (remove → add) all succeed.

## Failed request details (for service-side correlation)

### test2

- **Correlation ID**: `(see debug log)`

CLI error (from `--debug` log):
```
    "code": "UserError",
    "code": "UserError",
    "message": "Invalid containerUri https://6ec5159fc0c.blob.core.windows.net/mabables-r-c0297896-e148-53ce-99fc-86ee0d15760b",
azure.core.exceptions.HttpResponseError: (UserError) Invalid containerUri https://6ec5159fc0c.blob.core.windows.net/mabables-r-c0297896-e148-53ce-99fc-86ee0d15760b
Code: UserError
Message: Invalid containerUri https://6ec5159fc0c.blob.core.windows.net/mabables-r-c0297896-e148-53ce-99fc-86ee0d15760b
ERROR: cli: None
azure.core.exceptions.HttpResponseError: (UserError) Invalid containerUri https://6ec5159fc0c.blob.core.windows.net/mabables-r-c0297896-e148-53ce-99fc-86ee0d15760b
Code: UserError
Message: Invalid containerUri https://6ec5159fc0c.blob.core.windows.net/mabables-r-c0297896-e148-53ce-99fc-86ee0d15760b
```

### test4

- **Correlation ID**: `00ce5131-659b-4a3f-92b1-0b9b4354da72`
- **HTTP status**: 404

Response headers:
```
HTTP/2 404 
date: Tue, 21 Apr 2026 16:07:16 GMT
content-type: application/json; charset=utf-8
content-length: 938
vary: Accept-Encoding
request-context: appId=cid-v1:2d2e8e63-272e-4b3c-8598-4ee570a0e70d
x-ms-response-type: error
mise-correlation-id: 00ce5131-659b-4a3f-92b1-0b9b4354da72
strict-transport-security: max-age=31536000; includeSubDomains; preload
x-content-type-options: nosniff
azureml-served-by-cluster: vienna-eastus2-02
x-request-time: 0.279

```

Response body:
```json
{
    "error": {
        "code": "UserError",
        "severity": null,
        "message": "Could not find asset with ID: azureml://registries/mabables-reg-feb26/environments/vllm-server/versions/2",
        "messageFormat": null,
        "messageParameters": null,
        "referenceCode": null,
        "detailsUri": null,
        "target": null,
        "details": [],
        "innerError": {
            "code": "NotFoundError",
            "innerError": null
        },
        "debugInfo": null,
        "additionalInfo": null
    },
    "correlation": {
        "operation": "cdcafc0db8a7bbc69c8de83e8c2cede3",
        "request": "40268fe82e1f63f2",
        "RequestId": "40268fe82e1f63f2"
    },
    "environment": "eastus2",
    "location": "eastus2",
    "time": "2026-04-21T16:07:16.0726504+00:00",
    "componentName": "modelregistry",
    "code": "NotFound",
    "statusCode": 404,
    "message": "Could not find asset with ID: azureml://registries/mabables-reg-feb26/environments/vllm-server/versions/2",
    "details": []
}
```

### test5

- **Correlation ID**: `f270f6de-81cd-412a-98d5-d1c42e6e23f7`
- **HTTP status**: 404

Response headers:
```
HTTP/2 404 
date: Tue, 21 Apr 2026 16:07:20 GMT
content-type: application/json; charset=utf-8
content-length: 937
vary: Accept-Encoding
request-context: appId=cid-v1:2d2e8e63-272e-4b3c-8598-4ee570a0e70d
x-ms-response-type: error
mise-correlation-id: f270f6de-81cd-412a-98d5-d1c42e6e23f7
strict-transport-security: max-age=31536000; includeSubDomains; preload
x-content-type-options: nosniff
azureml-served-by-cluster: vienna-eastus2-02
x-request-time: 0.182

```

Response body:
```json
{
    "error": {
        "code": "UserError",
        "severity": null,
        "message": "Could not find asset with ID: azureml://registries/mabables-reg-feb26/environments/vllm-server/versions/1",
        "messageFormat": null,
        "messageParameters": null,
        "referenceCode": null,
        "detailsUri": null,
        "target": null,
        "details": [],
        "innerError": {
            "code": "NotFoundError",
            "innerError": null
        },
        "debugInfo": null,
        "additionalInfo": null
    },
    "correlation": {
        "operation": "88f1064d06c9cfe7364bbd8c4558d7b3",
        "request": "d2c7300a8bf7649b",
        "RequestId": "d2c7300a8bf7649b"
    },
    "environment": "eastus2",
    "location": "eastus2",
    "time": "2026-04-21T16:07:20.042865+00:00",
    "componentName": "modelregistry",
    "code": "NotFound",
    "statusCode": 404,
    "message": "Could not find asset with ID: azureml://registries/mabables-reg-feb26/environments/vllm-server/versions/1",
    "details": []
}
```


## Log files

All files in: `/Users/mabables/CODE/REPOS/deployment-template-demo/bugs/repro-logs/2026-04-21_09-05-21/`

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
