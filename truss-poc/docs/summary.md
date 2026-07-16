# Truss on AzureML — Executive Summary

## Objective

Validate whether Truss can serve as a portable model-packaging format on AzureML managed online endpoints via deployment templates.

## Verdict: Compatible through an adapter

Truss images **cannot be used unchanged** on AzureML managed endpoints, but the gap is bridgeable with a lightweight build-time adapter.

## What worked without modification

| Capability | Status |
|---|---|
| Truss model interface (`load()` + `predict()`) | Works as-is |
| Truss server (FastAPI/Uvicorn on port 8080) | Works as-is |
| Health endpoint (`GET /` → 200) | Works as-is |
| Readiness endpoint (`GET /v1/models/model`) | Works as-is |
| Prediction endpoint (`POST /v1/models/model:predict`) | Works as-is |
| OpenAI-compatible endpoints (`/v1/chat/completions`) | Built into Truss server — available for milestone 2 |
| `truss image build-context` for OCI image generation | Works, generates valid Dockerfile + server code |
| Model code portability | Same `model.py` runs locally and on AzureML |
| Environment variable passing via deployment template | Works — Truss reads `INFERENCE_SERVER_PORT` from env |
| GPU detection and usage | Works (CUDA available, model loads on GPU) |
| Offline mode (`HF_HUB_OFFLINE`, `TRANSFORMERS_OFFLINE`) | Works |

## Required AzureML-specific adaptations

| Adaptation | Effort | Why |
|---|---|---|
| **runit process supervisor** | ~5 lines in Dockerfile | AzureML requires `runsvdir /var/runit` as entrypoint |
| **ENTRYPOINT override** | 1 line | Replace Truss `ENTRYPOINT ["python3", "/app/main.py"]` with `CMD ["runsvdir", "/var/runit"]` |
| **Model weight path fallback** | ~15 lines in model.py | AzureML sets `AZUREML_MODEL_DIR` to the mounted model path; when weights are baked in, code must fall back to container path |
| **Workspace vs registry env** | Operational | Registry Dockerfile-based environments often fail silently; use workspace environments for deployment |
| **Deployment YAML generation** | Script/template | Deployment template fields must be mapped to deployment YAML (scoring_port, probes, env vars) |

## Key numbers

| Metric | Value |
|---|---|
| Truss server port | 8080 |
| AzureML default probe port | 5001 (configurable via deployment template) |
| Image build time (remote) | ~15-20 minutes |
| Model load time (Qwen3.5-0.8B on A100) | ~5 seconds |
| Container image size | ~8 GB (with CUDA + model weights) |

## Responsibilities separation

- **Truss**: packaging format, Python dependencies, model code, model server, health/predict endpoints
- **Deployment Template**: instance type, probe config, env vars, request settings, scaling policy
- **AzureML**: provisioning, identity, networking, traffic routing, logs, lifecycle management

## Recommendation

Build a **configuration adapter** that:
1. Runs `truss image build-context` to generate the standard Truss container structure
2. Injects runit and the AzureML entrypoint override into the generated Dockerfile
3. Maps Truss `config.yaml` fields to deployment template YAML fields
4. Handles model weight path negotiation between baked-in and mounted approaches

This adapter is ~100 lines of shell/Python and bridges the gap completely.
