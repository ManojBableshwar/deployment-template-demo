# DT Change Bug — Repro Results

**Date**: 2026-04-21 15:28:45 UTC
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
| 1 | CLI `model update --set` | v1 | v1 (same) | PASS | ✅ PASS | exit=0 | `(see debug log)` |
| 2 | CLI `model update --set` | v1 | v3 | FAIL | ✅ FAIL | exit=1 | `(see debug log)` |
| 3 | MFE PATCH `add` | (none) | v2 | PASS | ✅ PASS | 202 | `fba1571a-8ae4-4742-808d-9fabe902ed86` |
| 4 | MFE PATCH `add` | v2 | v3 | FAIL | ✅ FAIL | 404 | `8b36a3f2-d357-4886-a571-effd7ed36821` |
| 5 | MFE PATCH `replace` | v2 | v1 | FAIL | ✅ FAIL | 404 | `a1edd604-ba03-47c0-88c7-8fa8e2b06f62` |
| 6 | MFE PATCH `remove` | v2 | (none) | PASS | ✅ PASS | 202 | `ff6df910-83cc-46fc-a7a8-9b9aa153dfe5` |
| 7 | Workaround `remove`+`add` | v1 | v2 | PASS | ✅ PASS | 202/202 | `69a407dc-6eb9-4181-8b6a-bad7f473b4ad / fdd0a9eb-20c3-4825-b698-8a99dd7e4848` |

## Totals

- **Tests**: 7
- **Behaved as expected**: 7
- **Unexpected result**: 0

## Request IDs for failed requests (for service-side correlation)

| Test | Request ID | HTTP | Response |
|------|------------|------|----------|
| test2 | `(see debug log)` | (CLI) | `` |
| test4 | `8b36a3f2-d357-4886-a571-effd7ed36821` | 404 | `{   "error": {     "code": "UserError",     "severity": null,     "message": "Could not find asset with ID: azureml://re` |
| test5 | `a1edd604-ba03-47c0-88c7-8fa8e2b06f62` | 404 | `{   "error": {     "code": "UserError",     "severity": null,     "message": "Could not find asset with ID: azureml://re` |

## Log files

All files in: `/Users/mabables/CODE/REPOS/deployment-template-demo/bugs/repro-logs/2026-04-21_08-28-45/`

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
