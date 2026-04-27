# DT Change Bug — Repro Results

**Date**: 2026-04-21 15:26:32 UTC
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

| # | Method | From DT | To DT | Expected | Result | HTTP | Request ID |
|---|--------|---------|-------|----------|--------|------|------------|
| 1 | CLI `model update --set` | v1 | v1 (same) | PASS | ✅ PASS | exit=0 | `(CLI — see debug log)` |
| 2 | CLI `model update --set` | v1 | v3 | FAIL | ✅ FAIL | exit=1 | `(CLI — see debug log)` |
| 3 | MFE PATCH `add` | (none) | v2 | PASS | ✅ PASS | 202 | `` |
| 4 | MFE PATCH `add` | v2 | v3 | FAIL | ✅ FAIL | 404 | `` |
| 5 | MFE PATCH `replace` | v2 | v1 | FAIL | ✅ FAIL | 404 | `` |
| 6 | MFE PATCH `remove` | v2 | (none) | PASS | ✅ PASS | 202 | `` |
| 7 | Workaround `remove`+`add` | v1 | v2 | PASS | ✅ PASS | 202/202 | ` / ` |

## Totals

- **Tests**: 7
- **Behaved as expected**: 7
- **Unexpected result**: 0

## Request IDs for failed requests (for service-side correlation)

| Test | Request ID | HTTP | Response |
|------|------------|------|----------|
| test2 | `(n/a — CLI test, see debug log)` | (CLI) | `` |
| test4 | `` | 404 | `{   "error": {     "code": "UserError",     "severity": null,     "message": "Could not find asset with ID: azureml://re` |
| test5 | `` | 404 | `{   "error": {     "code": "UserError",     "severity": null,     "message": "Could not find asset with ID: azureml://re` |

## Log files

All files in: `/Users/mabables/CODE/REPOS/deployment-template-demo/bugs/repro-logs/2026-04-21_08-26-32/`

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
