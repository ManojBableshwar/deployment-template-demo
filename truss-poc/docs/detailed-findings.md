# Truss on AzureML Managed Online Endpoints — Detailed Findings

## 1. Overview

This PoC validates running a Truss-packaged Qwen/Qwen3.5-0.8B model on an AzureML managed online endpoint, deployed via a deployment template.

**Model**: Qwen/Qwen3.5-0.8B (0.8B parameters, ~1.6GB weights)
**SKU**: Standard_NC24ads_A100_v4
**Truss version**: 0.18.20
**Server framework**: Truss built-in (FastAPI/Uvicorn)

## 2. Truss produces a reusable OCI image

**Verdict: Yes, with caveats**

`truss image build-context` generates a complete Docker build context containing:
- A Dockerfile based on `baseten/truss-server-base:3.11-gpu-v0.13.0`
- The Truss server runtime (`truss_server.py`, `model_wrapper.py`, etc.)
- Model code (`model/model.py`)
- Pinned Python dependencies (`requirements.txt`, `constraints.txt`)
- Model configuration (`config.yaml`)

The generated image is OCI-compatible and can be built by any Docker-compatible system (including AzureML's remote ACR builder).

**Caveat**: The base image `baseten/truss-server-base` is maintained by Baseten and may contain Baseten-specific optimizations or telemetry. For production use, consider vendoring the server code or using a neutral base image.

## 3. Truss server runs without Baseten services

**Verdict: Yes**

The Truss server runs fully standalone:
- No Baseten API key required
- No `truss push` or Baseten deployment needed
- No outbound calls to Baseten services at runtime
- Server starts with `python3 /app/main.py` and listens on port 8080

The only Baseten dependency is the base Docker image (`baseten/truss-server-base`), which could be replaced with a custom image if needed.

## 4. Scoring path and port

### Port
- **Truss default**: 8080 (via `INFERENCE_SERVER_PORT` env var)
- **AzureML vLLM default**: 8000
- **AzureML default probe port**: 5001 (historical, now configurable via deployment template)

The port mismatch is handled via the deployment template's `scoring_port: 8080` field.

### Paths
| Endpoint | Path | Method |
|---|---|---|
| Liveness | `/` | GET |
| Readiness | `/v1/models/model` | GET |
| Truss predict | `/v1/models/model:predict` | POST |
| OpenAI chat | `/v1/chat/completions` | POST |
| OpenAI completions | `/v1/completions` | POST |
| OpenAI embeddings | `/v1/embeddings` | POST |
| SageMaker ping | `/ping` | GET |
| SageMaker invocations | `/invocations` | POST |

**Key finding**: Truss server v0.18.20 **natively exposes `/v1/chat/completions`**, `/v1/completions`, `/v1/embeddings`, and `/v1/messages` (Anthropic-style). These are built into the server regardless of whether the model implements them. The model's `predict()` method is called internally — the routing is handled by the Truss server framework.

### OpenAI-compatible endpoint for Milestone 2 (TRT-LLM/vLLM)

For milestone 2 with TRT-LLM or vLLM as the inference backend inside Truss:

**To make `/v1/chat/completions` work, the model class needs to implement `chat_completions()` or route internally.** The Truss server has the route wired up, but it calls the model's corresponding method. If the model only implements `predict()`, the chat endpoint will return an error.

Options for wrapping `/v1/chat/completions` in a Truss app:
1. **Implement `async def chat_completions(self, request)`** in `model.py` — Truss server will route to it automatically
2. **Use Truss's TRT-LLM runtime** (`runtime: trt_llm` in config.yaml) — this provides native OpenAI-compatible endpoints
3. **Run vLLM as a subprocess** inside the Truss container and proxy `/v1/chat/completions` to vLLM's endpoint — more complex but reuses proven vLLM serving

## 5. Request and response format

### Truss native predict

**Request** (`POST /v1/models/model:predict`):
```json
{
  "prompt": "What is the capital of France?",
  "max_new_tokens": 50,
  "temperature": 0.1
}
```

**Response**:
```json
{
  "generated_text": "The capital of France is Paris.",
  "usage": {
    "prompt_tokens": 7,
    "completion_tokens": 6
  }
}
```

### Format differences from AzureML standard
- AzureML's default scoring path is `/score` — Truss uses `/v1/models/model:predict`
- The deployment template's `scoring_path: /` maps the AzureML scoring URI to the container's root, which is the liveness endpoint. Actual inference goes through the full path.

## 6. Environment variables and secrets

### Environment variables set via deployment template
| Variable | Value | Purpose |
|---|---|---|
| `INFERENCE_SERVER_PORT` | `8080` | Truss server port |
| `MODEL_WEIGHTS_PATH` | `/app/model-weights` | Fallback weights path |
| `HF_HUB_OFFLINE` | `1` | Disable HuggingFace Hub |
| `TRANSFORMERS_OFFLINE` | `1` | Disable transformers downloads |
| `PYTHONUNBUFFERED` | `1` | Real-time logging |

### AzureML-injected environment variables
| Variable | Value | Impact |
|---|---|---|
| `AZUREML_MODEL_DIR` | `/var/azureml-app/azureml-models/{name}/{version}` | Overrides model path — requires fallback logic in model code |
| Various AzureML internals | (auto-set) | No impact on Truss server |

### Secrets
- No Baseten API key needed
- No HuggingFace token needed (model is public and baked in / mounted)
- AzureML endpoint authentication (key-based) is handled externally

## 7. Model weight handling

### Approach A: Baked into container (implemented)
- Weights downloaded from HuggingFace during Docker build (`RUN python3 -c "from huggingface_hub import snapshot_download; ..."`)
- Image size: ~8GB (CUDA runtime + PyTorch + model weights)
- Pros: Self-contained, no model registration needed, deterministic
- Cons: Large image, rebuild required for weight changes

### Approach B: Mounted via AzureML model registration (validated)
- AzureML sets `AZUREML_MODEL_DIR` and mounts weights at runtime
- Model code checks for `config.json` in `AZUREML_MODEL_DIR` before falling back to baked-in
- Pros: Smaller image, weights managed separately
- Cons: Requires model registration, upload via azcopy for large models

### Key issue discovered
When both baked-in weights exist AND `AZUREML_MODEL_DIR` is set (which AzureML always does when a model is referenced), the model code must implement fallback logic. `AZUREML_MODEL_DIR` may point to a dummy model (just model.py code) rather than actual weights.

## 8. Startup time

| Phase | Duration |
|---|---|
| Container pull + start | ~2-5 minutes |
| Truss server startup (Uvicorn) | < 1 second |
| Model load (Qwen3.5-0.8B on A100) | ~3-5 seconds |
| **Total cold start** | **~3-6 minutes** |

Compare with vLLM deployment: ~5-10 minutes (vLLM engine initialization is heavier).

## 9. Health and readiness probes

### Configuration
```yaml
liveness_probe:
  path: /           # Truss returns `true` at root
  port: 8080
  initial_delay: 600  # 10 min for image build + model load
  period: 10

readiness_probe:
  path: /v1/models/model  # Returns model status
  port: 8080
  initial_delay: 600
  period: 10
```

### Port 5001 behavior (verification)
The deployment template's probe port configuration (8080) was respected. The historical port 5001 issue appears to be resolved. No nginx sidecar was needed.

**Caveat**: The liveness probe error message "Liveness probe failed: Get ." in early attempts was caused by model loading failure (container crashed), not by port misconfiguration. Once the model loaded successfully, probes on port 8080 worked.

## 10. AzureML authentication

- Endpoint uses `auth_mode: key` (AzureML-managed)
- Authentication is completely external to the Truss container
- No changes needed in Truss model code for auth
- Requests reach the container already authenticated

## 11. Logging and Azure Monitor visibility

- Truss server logs via Python's logging module (JSON format)
- Logs are captured by `az ml online-deployment get-logs`
- Model code `print()` statements appear in logs
- runit service script output appears in logs
- **Gap**: Truss uses `loguru` internally, which may not integrate with Azure Monitor's structured logging. Custom log handlers may be needed for production.

## 12. CPU/GPU resource mapping

| Truss config field | AzureML deployment template field | Mapping |
|---|---|---|
| `resources.cpu` | N/A (determined by instance type) | AzureML controls via SKU |
| `resources.memory` | N/A (determined by instance type) | AzureML controls via SKU |
| `resources.use_gpu` | `default_instance_type` | Must choose GPU SKU |
| `resources.accelerator` | `allowed_instance_types` | Manual mapping needed |

**Gap**: Truss's resource specification is abstract ("A100", "4 CPUs, 16GB"). AzureML requires specific SKU names (`Standard_NC24ads_A100_v4`). An adapter would need a mapping table.

## 13. Truss config → Deployment template field mapping

| Truss `config.yaml` | Deployment Template | Notes |
|---|---|---|
| `model_name` | `name` (partial) | DT name includes model + serving info |
| `python_version` | N/A | Baked into container |
| `requirements` | N/A | Baked into container |
| `resources.use_gpu` | `default_instance_type` | Requires SKU mapping |
| `resources.accelerator` | `allowed_instance_types` | Requires SKU mapping |
| `environment_variables` | `environment_variables` | Direct mapping |
| N/A | `scoring_port` | Always 8080 for Truss |
| N/A | `scoring_path` | Always `/` for Truss |
| N/A | `liveness_probe` | Standard Truss: GET / on 8080 |
| N/A | `readiness_probe` | Standard Truss: GET /v1/models/{name} on 8080 |
| N/A | `request_settings` | AzureML-specific, no Truss equivalent |
| `runtime.predict_concurrency` | `request_settings.max_concurrent_requests_per_instance` | Approximate mapping |

### Properties that remain runtime-specific (inside container)
- Python version and dependencies
- Model code (`model.py`)
- Truss server configuration
- Model weight location within the container
- Truss server port (always 8080)
- Internal batching/concurrency

### Properties managed by deployment template
- Instance type and count
- Probe configuration
- Request timeout and concurrency limits
- Environment variables
- Model mount path
- Scaling rules

## 14. Security concerns

1. **Base image trust**: `baseten/truss-server-base` is a third-party image. For production, pin digests and scan for vulnerabilities.
2. **Build-time downloads**: Model weights downloaded from HuggingFace during build. In regulated environments, use pre-downloaded artifacts.
3. **No secret isolation**: Truss's built-in secrets mechanism (`secrets:` in config.yaml) is designed for Baseten's secret management. AzureML secrets should use Key Vault references.
4. **Telemetry**: Truss server may send anonymous telemetry. Set `TRUSS_NO_USAGE_STATS=1` to disable.
5. **Network access**: Container should have `HF_HUB_OFFLINE=1` to prevent runtime downloads. Verified working.

## 15. Product gaps

| Gap | Severity | Workaround |
|---|---|---|
| No native runit support | Medium | Add runit in Dockerfile (3 lines) |
| No AzureML model path awareness | Medium | Fallback logic in model.py (~15 lines) |
| Registry Dockerfile envs fail silently | High | Use workspace environments instead |
| No Truss → DT config translator | Medium | Manual mapping or script |
| Truss assumes Baseten deployment model | Low | All Baseten-specific code is optional |
| No streaming support validation | Medium | Needs Milestone 2 testing |
| Package version conflicts (transformers) | Medium | Override in Dockerfile after base install |

## 16. Recommendation

### Verdict: Compatible through an adapter

A lightweight adapter (~100-200 lines) can bridge Truss and AzureML:

1. **`truss-to-azureml build`**: Run `truss image build-context`, inject runit, override entrypoint
2. **`truss-to-azureml config`**: Map `config.yaml` → deployment template YAML
3. **`truss-to-azureml deploy`**: Create environment, model, endpoint, deployment

This keeps Truss as the packaging format while AzureML owns infrastructure. The adapter is stateless and can be a CLI tool or CI/CD step.

### For Foundry Managed Compute integration

Foundry could:
1. Accept Truss projects as a packaging format alongside its existing formats
2. Run `truss image build-context` internally during environment creation
3. Inject the runit adapter automatically
4. Map Truss config to deployment template fields
5. Handle model weight mounting via the existing model registration flow

This would make Truss a first-class citizen without requiring users to know about AzureML-specific adaptations.
