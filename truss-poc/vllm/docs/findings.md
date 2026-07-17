# Truss + vLLM on AzureML — Findings (Milestone 2)

## Summary

This sample runs Qwen/Qwen3.5-0.8B on an AzureML managed online endpoint using
**Truss's `docker_server` backend** wrapping the official **vLLM** image the repo
already uses (`vllm/vllm-openai:latest`). It is the practical answer to
"milestone 2 = TRT-LLM": Truss's *native* TRT-LLM backend (Briton) is
Baseten-coupled and not viable here (see §5), so `docker_server` + vLLM is the
adapter path that runs standalone on AzureML.

Two things this sample proves that the transformers sample did not:
1. **`/v1/chat/completions` is native** (vLLM serves it; no custom method).
2. **Weights are mounted at runtime** (`/opt/ml/model`), **not baked** into the image.

## 1. Truss `docker_server` architecture

`truss image build-context` (from `config.yaml` with a `docker_server:` block)
generates a container that wraps vLLM:

```
FROM vllm/vllm-openai:latest
  + nginx        reverse proxy (patched to :5001)
  + supervisord  init / process manager (replaces runit)
  ├─ program:model-server → bash /app/vllm-launch.sh   (vLLM OpenAI server :8000)
  └─ program:nginx        → nginx -g "daemon off;"     (proxy :5001)
ENTRYPOINT supervisord
```

nginx route mapping (Truss-generated):

| AzureML request | nginx action | vLLM endpoint |
|---|---|---|
| `GET /` | rewrite → `/health` | liveness |
| `GET /v1/models/model` | rewrite → `/health` | readiness |
| `POST /v1/models/model:predict` | rewrite → `/v1/chat/completions` | Truss-native predict |
| `POST /v1/chat/completions` | passthrough | **native OpenAI** |
| `GET /v1/models`, `/v1/completions`, … | passthrough | native vLLM |

## 2. AzureML adaptations (3 patches to the Truss-generated context)

| # | Patch | Why |
|---|---|---|
| 1 | `proxy.conf`: `listen 8080` → `5001` | AzureML's fixed probe/scoring port |
| 2 | Revert apt mirror (`mirror://mirrors.ubuntu.com/US.txt` → `archive.ubuntu.com`) | Truss's mirror rewrite 404s in the AzureML ACR build → `apt-get install nginx` fails (exit 100) |
| 3 | Add `vllm-launch.sh` + `COPY` in Dockerfile | Resolve the mounted model path; no baked weights |

Note: **no runit needed** — supervisord (Truss-generated) is the init process, so
this integration is *cleaner* than the transformers sample (which added runit).

## 3. Mounted weights (no baking)

- Model registered with the **AOT manifest** (`2b-register-model-manifest.sh`;
  startPendingUpload + azcopy + `aotManifest:True`) — required for DT deploys.
- DT sets `model_mount_path: /opt/ml/model`.
- `vllm-launch.sh` resolves the mounted path (`AZUREML_MODEL_DIR` → `/opt/ml/model`,
  finds `config.json`) and runs `vllm ... --model <path>`.
- The image contains **no model weights** — only the vLLM runtime.

## 4. Image build gotcha (apt mirrors)

Both the registry **and** workspace ACR builds first failed on
`apt-get install nginx` with `exit code 100` — Truss rewrites apt sources to
community mirrors (`mirror://mirrors.ubuntu.com/US.txt`) that return 404 / sync
errors in the AzureML build network. Reverting to `archive.ubuntu.com` fixes it.
(The transformers sample didn't hit this because its custom Dockerfile didn't
carry Truss's mirror rewrite + apt install.)

## 5. Why NOT Truss's native TRT-LLM (Briton)

Truss's `trt_llm` backend is **Briton**, Baseten's proprietary engine:
- The extension imports `from briton.truss_model import Model`.
- `Model.load()` calls `briton_interactor.load(engine_path=…)` — it expects a
  **pre-built TRT engine** and launches the **Briton C++ binary** at `/usr/local/briton/`.
- `truss image build-context` for `trt_llm` emits an **empty `requirements.txt`** —
  it installs neither Briton nor TensorRT-LLM nor builds the engine.

Those steps (checkpoint → GPU-specific TRT engine compile → Briton packaging)
run **server-side in Baseten's engine builder during `truss push`**, which is not
available off-Baseten. Hence native Truss-TRT-LLM **cannot** run on AzureML — the
`docker_server` + vLLM (or NVIDIA `trtllm-serve`) path is the standalone
alternative. This directly hits the PoC guardrail (documented, not silently swapped).

## 6. `/v1/chat/completions` availability (the triple-verify)

| Backend | `/v1/chat/completions` |
|---|---|
| transformers (`TrussServer`) | needs a custom `chat_completions()` method (returns **424** here) |
| **vLLM (`docker_server`)** | **native** — vLLM serves it; Truss nginx passes it through |
| TRT-LLM V2 (`docker_server`/Briton) | native (`predict_endpoint: /v1/chat/completions`) — but Baseten-coupled |

## 7. Deployment result

_(populated after the live deployment verification — see `../logs/` and the
top-level findings.)_
