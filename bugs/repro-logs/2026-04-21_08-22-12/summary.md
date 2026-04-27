# DT Change Bug — Repro Results

**Date**: 2026-04-21 15:22:12 UTC
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
| 1 | CLI `model update --set` | v1 | v1 (same) | PASS | ⚠️ FAIL | exit=2 | `(CLI — see debug log)` |
| 2 | CLI `model update --set` | v1 | v3 | FAIL | ✅ FAIL | exit=2 | `(CLI — see debug log)` |
