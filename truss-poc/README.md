# Truss on AzureML — PoC (two backend samples)

Validates running **Truss-packaged models** on **AzureML managed online endpoints**
through **Foundry/AML deployment templates**. Two parallel samples, one per Truss
backend, so you can diff them and see exactly what changes between backends.

```
truss-poc/
├── transformers/   ← Milestone 1: Truss default server (TrussServer) + HF transformers
│                      weights BAKED into the image; custom model.py (load/predict)
└── vllm/           ← Milestone 2: Truss docker_server + official vLLM image
                       weights MOUNTED at runtime; no model.py; native /v1/chat/completions
```

Both deploy Qwen/Qwen3.5-0.8B on `Standard_NC24ads_A100_v4` via the same
deployment-template-inheritance flow (slim deployment YAML + DT + AOT-manifest model).

## How to diff the two samples

```bash
# Backend selection (the core difference)
diff transformers/truss-model/config.yaml           vllm/truss-model/config.yaml

# Deployment template (env vars, mount path, probes)
diff transformers/yaml/deployment-template.yml      vllm/yaml/deployment-template.yml

# Deployment YAML (backend-agnostic — only model + DT ref differ)
diff transformers/yaml/deployment.yml               vllm/yaml/deployment.yml

# Environment (Dockerfile-based vs Truss docker_server generated)
diff transformers/yaml/environment.yml              vllm/yaml/environment.yml

# Pipeline scripts (mostly identical; env.sh names + step 1 + step 7 differ)
diff transformers/scripts/1-create-environment.sh   vllm/scripts/1-create-environment.sh
```

## Key differences at a glance

| Aspect | transformers | vllm |
|---|---|---|
| Truss backend | `TrussServer` (default) | `docker_server` |
| Model code | `model/model.py` (`load`/`predict`) | none (wraps vLLM) |
| Base image | `nvidia/cuda:...` + Truss server | `vllm/vllm-openai:latest` |
| Process init | runit (`runsvdir`) | supervisord (Truss-generated) |
| Weights | **baked into image** (HF download at build) | **mounted at runtime** (`/opt/ml/model`) |
| `/v1/chat/completions` | needs custom method (returns 424 here) | **native** (vLLM serves it) |
| Scoring port | 5001 (Truss server) | 5001 (nginx → vLLM 8000) |
| Predict route | `/v1/models/model:predict` (native) | `/v1/models/model:predict` → `/v1/chat/completions` |

## What's shared (both samples)
- **DT-inheritance**: slim `deployment.yml` + `deploymentTemplateOverride`; env_vars/probes/port inherited from the DT.
- **AOT manifest**: model registered via `2b-register-model-manifest.sh` (startPendingUpload + azcopy + `aotManifest:True`) — required or DT deploys fail with `InvalidModelFeed`.
- **Model→DT tagging**: `3b-tag-model-dt.sh` (MFE PATCH).
- **Port 5001**: AzureML's fixed probe/scoring port.

See each sample's `docs/` for detailed findings. The overarching finding: Truss is
**compatible through an adapter** — the `TrussServer` and `docker_server` backends
run on AzureML unchanged-ish; only the Baseten-coupled `trt_llm`/Briton backend does not.
