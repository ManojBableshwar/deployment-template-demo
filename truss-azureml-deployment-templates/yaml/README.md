# YAML reference — Truss + vLLM on AzureML

Reference / scaffolding copies of the config files that the
[`../build-test-promote.ipynb`](../build-test-promote.ipynb) notebook generates at runtime.

> **Not standalone.** The notebook is the source of truth — it also builds the container image,
> registers the model *with an AOT manifest* (via REST, not a YAML), pushes the image, and links the
> model to the deployment template. These files are a **quick reference and base scaffolding** to build on.
>
> **Fill in the placeholders** before use: `<your-registry>`, `<your-acr>`, `<rg>` (resource group),
> `<ws>` (workspace). Bump the version numbers per iteration. Asset names (`truss-vllm-*`) are just
> examples — rename freely, but keep them consistent across files.

## Order of operations

| # | File | Produces |
|---|------|----------|
| 1 | `config.yaml` | the container image (build with Truss, push to your ACR) |
| 2 | `environment.yml` | an AzureML environment → then shared into the registry |
| — | *(model)* | registered **with an AOT manifest** — REST, see notebook Step 8 (no YAML) |
| 3 | `deployment-template.yml` | the registry Deployment Template → then linked to the model (REST, notebook Step 11) |
| 4 | `endpoint.yml` | the online endpoint |
| 5 | `deployment.yml` | the deployment (inherits the contract from the DT) |

## Files & commands

### `config.yaml` — Truss package descriptor
Declares the serving contract: `docker_server` over `vllm/vllm-openai`, `server_port: 8000`,
`predict_endpoint: /v1/chat/completions`, `/health` probes, weights mounted at `/opt/ml/model`.
Consumed by **Truss** (not `az`):
```bash
truss image build-context ./build-ctx .          # run from the dir holding config.yaml
cd build-ctx && docker build -t <your-acr>.azurecr.io/truss-vllm-server:1 .
docker push <your-acr>.azurecr.io/truss-vllm-server:1
```

### `environment.yml` — AzureML environment (image-based)
Points an environment at the pushed image, then promotes it into the registry.
```bash
az ml environment create --file environment.yml -g <rg> -w <ws>
az ml environment share --name truss-vllm-server --version 1 -g <rg> -w <ws> \
  --registry-name <your-registry> --share-with-name truss-vllm-server --share-with-version 1
```

### `deployment-template.yml` — Deployment Template (registry)
The serving contract AzureML applies — **mirrors `config.yaml`** (`scoring_port: 8000`,
`scoring_path: /v1/chat/completions`, `/health` probes, `model_mount_path: /opt/ml/model`).
```bash
az ml deployment-template create --file deployment-template.yml --registry-name <your-registry> --version 1
```
> After creating it, **link the model** to the template (default + allowed) via a model-registry
> REST PATCH — see notebook Step 11. Creating the template alone is not enough for DT-based deploy.

### `endpoint.yml` — Managed online endpoint
```bash
az ml online-endpoint create --file endpoint.yml -g <rg> -w <ws>
```

### `deployment.yml` — Managed online deployment (DT-override)
Slim: it only names the model + instance and points at the DT via
`properties.azureml.deploymentTemplateOverride`. Port, path, probes, mount, and env vars are
**inherited** from the DT — do not duplicate them.
```bash
az ml online-deployment create --file deployment.yml -g <rg> -w <ws> --all-traffic
```

## Notes
- **Model registration is not a YAML step here.** DT-based deployment requires the model's **AOT
  manifest**, produced via `startPendingUpload` → `azcopy` → PUT with `aotManifest: "True"`
  (notebook Step 8). A plain `az ml model create` does **not** produce it (→ `InvalidModelFeed`).
- Keep the DT's `scoring_port` / `scoring_path` / probes **in sync with `config.yaml`** — that mirroring
  is the whole point of the faithful mapping.
- Weights are **mounted** at `/opt/ml/model` at runtime, not baked into the image.
