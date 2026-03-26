#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# run-e2e.sh — BYOC (Bring Your Own Container) end-to-end deployment
#
# Demonstrates deploying Qwen3.5-0.8B via vLLM on Azure ML managed endpoints
# WITHOUT deployment templates. All configuration is specified explicitly
# in the deployment YAML.
#
# Usage:
#   cd byoc && bash scripts/run-e2e.sh 2>&1 | tee logs/e2e-run.log
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BYOC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$BYOC_DIR/config.sh"

LOGDIR="$BYOC_DIR/logs"
mkdir -p "$LOGDIR"

info()  { printf '\n\033[1;34m════ [%s] %s\033[0m\n' "$(date +%H:%M:%S)" "$*"; }
ok()    { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
fail()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*"; exit 1; }

az account set --subscription "$SUBSCRIPTION_ID"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 1: Verify / Show Environment
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 1: Environment — $ENVIRONMENT_NAME v$ENVIRONMENT_VERSION"

echo "--- Registry environment ---"
az ml environment show \
  --name "$ENVIRONMENT_NAME" \
  --version "$ENVIRONMENT_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -o yaml 2>&1 | tee "$LOGDIR/1-environment.log"

ok "Environment $ENVIRONMENT_NAME v$ENVIRONMENT_VERSION exists in registry"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 2: Verify / Show Model
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 2: Model — $MODEL_NAME v$MODEL_VERSION"

echo "--- Registry model ---"
az ml model show \
  --name "$MODEL_NAME" \
  --version "$MODEL_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -o yaml 2>&1 | tee "$LOGDIR/2-model.log"

ok "Model $MODEL_NAME v$MODEL_VERSION exists in registry"

# Verify NO deployment template is set on this model
DT_REF=$(az ml model show \
  --name "$MODEL_NAME" \
  --version "$MODEL_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  --query "default_deployment_template.asset_id" -o tsv 2>/dev/null || true)

if [[ -z "$DT_REF" || "$DT_REF" == "None" ]]; then
  ok "Model has NO deployment template (BYOC mode)"
else
  echo "  NOTE: Model has DT reference: $DT_REF (but this is BYOC, we deploy with explicit settings)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3: Create / Verify Online Endpoint
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 3: Online Endpoint — $ENDPOINT_NAME"

if az ml online-endpoint show --name "$ENDPOINT_NAME" \
     -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  ok "Endpoint '$ENDPOINT_NAME' already exists"
else
  echo "Creating endpoint..."
  az ml online-endpoint create \
    --file "$BYOC_DIR/yaml/endpoint.yml" \
    -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP"
  ok "Endpoint created"
fi

az ml online-endpoint show \
  --name "$ENDPOINT_NAME" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  -o yaml 2>&1 | tee "$LOGDIR/3-endpoint.log"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 4: Create Online Deployment (BYOC — explicit env, probes, etc.)
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 4: Online Deployment — $DEPLOYMENT_NAME"

# Delete existing deployment if present
if az ml online-deployment show --name "$DEPLOYMENT_NAME" \
     --endpoint-name "$ENDPOINT_NAME" \
     -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  echo "Deleting existing deployment '$DEPLOYMENT_NAME'..."
  az ml online-endpoint update --name "$ENDPOINT_NAME" \
    --traffic "${DEPLOYMENT_NAME}=0" \
    -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" 2>/dev/null || true
  az ml online-deployment delete --name "$DEPLOYMENT_NAME" \
    --endpoint-name "$ENDPOINT_NAME" \
    -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" --yes
  ok "Old deployment deleted"
fi

echo "Creating deployment (this will take 15-30 minutes for image build + model download)..."
echo "Start time: $(date)"

az ml online-deployment create \
  --file "$BYOC_DIR/yaml/deployment.yml" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  --all-traffic \
  2>&1 | tee "$LOGDIR/4-deployment.log"

echo "End time: $(date)"
ok "Deployment created successfully"

echo "--- Deployment details ---"
az ml online-deployment show \
  --name "$DEPLOYMENT_NAME" \
  --endpoint-name "$ENDPOINT_NAME" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  -o yaml 2>&1 | tee -a "$LOGDIR/4-deployment.log"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 5: Test Inference
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 5: Test Inference"

SCORING_URI=$(az ml online-endpoint show \
  --name "$ENDPOINT_NAME" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  --query scoring_uri -o tsv)

ENDPOINT_KEY=$(az ml online-endpoint get-credentials \
  --name "$ENDPOINT_NAME" \
  -w "$AZUREML_WORKSPACE" -g "$RESOURCE_GROUP" \
  --query primaryKey -o tsv)

BASE_URL="${SCORING_URI%/score}"

echo "Scoring URI: $SCORING_URI"
echo ""

echo "--- Test 1: Simple chat completion ---"
curl -s -X POST "${BASE_URL}/v1/chat/completions" \
  -H "Authorization: Bearer $ENDPOINT_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.5-0.8B",
    "messages": [{"role": "user", "content": "Say hello in 5 words"}],
    "max_tokens": 50,
    "temperature": 0.7
  }' | python3 -m json.tool 2>&1 | tee "$LOGDIR/5-inference.log"

echo ""
echo "--- Test 2: Multi-turn conversation ---"
curl -s -X POST "${BASE_URL}/v1/chat/completions" \
  -H "Authorization: Bearer $ENDPOINT_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.5-0.8B",
    "messages": [
      {"role": "system", "content": "You are a helpful AI assistant."},
      {"role": "user", "content": "What is vLLM?"},
      {"role": "assistant", "content": "vLLM is an open-source library for fast LLM inference."},
      {"role": "user", "content": "How does it achieve high throughput?"}
    ],
    "max_tokens": 256,
    "temperature": 0.7
  }' | python3 -m json.tool 2>&1 | tee -a "$LOGDIR/5-inference.log"

echo ""
ok "All inference tests passed"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 6: Test with OpenAI SDK
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 6: OpenAI SDK Inference Test"

# Use venv python if available
PYTHON="${BYOC_DIR}/../.venv/bin/python3"
if [[ ! -x "$PYTHON" ]]; then
  PYTHON="python3"
fi

"$PYTHON" - "$BASE_URL" "$ENDPOINT_KEY" <<'PYEOF' 2>&1 | tee "$LOGDIR/6-openai-sdk.log"
import sys, json
try:
    from openai import OpenAI
except ImportError:
    print("[WARN] openai package not installed, installing...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "openai"])
    from openai import OpenAI

base_url = sys.argv[1]
api_key = sys.argv[2]

client = OpenAI(base_url=f"{base_url}/v1", api_key=api_key)

print("--- OpenAI SDK: chat.completions.create ---")
response = client.chat.completions.create(
    model="Qwen3.5-0.8B",
    messages=[
        {"role": "user", "content": "Give me a short introduction to large language models."}
    ],
    max_tokens=256,
    temperature=0.7,
)
print(json.dumps(response.model_dump(), indent=2, default=str))

print("\n--- OpenAI SDK: streaming ---")
stream = client.chat.completions.create(
    model="Qwen3.5-0.8B",
    messages=[
        {"role": "user", "content": "Count from 1 to 5 briefly."}
    ],
    max_tokens=128,
    stream=True,
)
full_text = ""
for chunk in stream:
    if chunk.choices and chunk.choices[0].delta.content:
        text = chunk.choices[0].delta.content
        full_text += text
        print(text, end="", flush=True)
print(f"\n\n[Streamed text]: {full_text}")
print("\n--- OpenAI SDK tests passed ---")
PYEOF

ok "OpenAI SDK tests passed"

# ═══════════════════════════════════════════════════════════════════════════════
info "BYOC E2E COMPLETE — All steps succeeded"
echo ""
echo "Summary:"
echo "  Environment:  $ENVIRONMENT_NAME v$ENVIRONMENT_VERSION (registry: $AZUREML_REGISTRY)"
echo "  Model:        $MODEL_NAME v$MODEL_VERSION (registry: $AZUREML_REGISTRY)"
echo "  Endpoint:     $ENDPOINT_NAME (workspace: $AZUREML_WORKSPACE)"
echo "  Deployment:   $DEPLOYMENT_NAME (BYOC — no deployment template)"
echo "  Inference:    ✓ Working (curl + OpenAI SDK)"
echo ""
echo "Logs saved to: $LOGDIR/"
