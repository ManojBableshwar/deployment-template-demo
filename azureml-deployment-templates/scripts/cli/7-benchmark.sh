#!/usr/bin/env bash
# Step 7: Benchmark deployments with AIPerf (SKU-aware, parallel across GPUs)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

# Activate venv (aiperf installed there)
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VENV_DIR="$REPO_ROOT/.venv"
if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
  echo "[ERROR] venv not found at $VENV_DIR. Run: python3.13 -m venv .venv && pip install aiperf"
  exit 1
fi
source "$VENV_DIR/bin/activate"

az account set --subscription "$SUBSCRIPTION_ID"

read -ra SKUS <<< "${E2E_SKUS:-a100 h100}"
_step_start "Step 7: Benchmark endpoint (${SKUS[*]})"

# -- SKU helpers ---------------------------------------------------------------
sku_endpoint_name() {
  local dep_yaml="$YAML_DIR/deployment-${1}.yml"
  python3 -c "
import yaml
with open('$dep_yaml') as f:
    print(yaml.safe_load(f)['endpoint_name'])
" 2>/dev/null || grep '^endpoint_name:' "$dep_yaml" | awk '{print $2}'
}

# -- Fetch per-endpoint credentials -------------------------------------------
declare_creds() {
  local sku="$1"
  local ep_name
  ep_name=$(sku_endpoint_name "$sku")

  info "[$sku] Fetching credentials for $ep_name..."

  local scoring_uri api_key base_url
  scoring_uri=$(az ml online-endpoint show \
    --name "$ep_name" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query scoring_uri -o tsv)

  api_key=$(az ml online-endpoint get-credentials \
    --name "$ep_name" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query primaryKey -o tsv)

  base_url="${scoring_uri%/score}"
  base_url="${base_url%/}"

  eval "BASE_URL_${sku}=\"\$base_url\""
  eval "API_KEY_${sku}=\"\$api_key\""

  info "[$sku] Endpoint: $base_url"
}

for sku in "${SKUS[@]}"; do
  declare_creds "$sku"
done

# -- Benchmark config ---------------------------------------------------------
# Priority: benchmark-config.yml (hydrated by step 2) > env var > defaults
BENCH_CFG="$YAML_DIR/benchmark-config.yml"

if [[ -f "$BENCH_CFG" ]] && python3 -c "import yaml" 2>/dev/null; then
  # Read concurrencies from the hydrated YAML (persists across re-runs)
  _cfg_conc=$(python3 -c "
import yaml, sys
with open('$BENCH_CFG') as f:
    cfg = yaml.safe_load(f)
concs = cfg.get('benchmark', {}).get('concurrencies', [])
if concs:
    print(' '.join(str(c) for c in concs))
" 2>/dev/null || true)
  _cfg_mns=$(python3 -c "
import yaml, sys
with open('$BENCH_CFG') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('benchmark', {}).get('max_num_seqs', ''))
" 2>/dev/null || true)
  _cfg_req=$(python3 -c "
import yaml, sys
with open('$BENCH_CFG') as f:
    cfg = yaml.safe_load(f)
print(cfg.get('benchmark', {}).get('request_count', ''))
" 2>/dev/null || true)

  if [[ -n "$_cfg_conc" ]]; then
    read -ra CONCURRENCIES <<< "$_cfg_conc"
    info "Using concurrencies from benchmark-config.yml (max_num_seqs=${_cfg_mns:-?}): ${CONCURRENCIES[*]}"
  elif [[ -n "${BENCHMARK_CONCURRENCIES:-}" ]]; then
    read -ra CONCURRENCIES <<< "$BENCHMARK_CONCURRENCIES"
    info "Using calculated concurrencies (max_num_seqs=${VLLM_MAX_NUM_SEQS:-?}): ${CONCURRENCIES[*]}"
  else
    CONCURRENCIES=(2 4 8 16 24 48 96)
    info "Using default concurrencies: ${CONCURRENCIES[*]}"
  fi
  REQUEST_COUNT="${_cfg_req:-100}"
elif [[ -n "${BENCHMARK_CONCURRENCIES:-}" ]]; then
  read -ra CONCURRENCIES <<< "$BENCHMARK_CONCURRENCIES"
  info "Using calculated concurrencies (max_num_seqs=${VLLM_MAX_NUM_SEQS:-?}): ${CONCURRENCIES[*]}"
  REQUEST_COUNT=100
else
  CONCURRENCIES=(2 4 8 16 24 48 96)
  info "Using default concurrencies: ${CONCURRENCIES[*]}"
  REQUEST_COUNT=100
fi
TOKEN_CONFIGS=(
  "200 800 short-gen"
  "800 200 short-prompt"
  "2000 8000 long-gen"
  "8000 2000 long-prompt"
)
BENCH_MODEL="model"

# -- Output directory ---------------------------------------------------------
if [[ -n "${E2E_LOG_DIR:-}" ]]; then
  BENCH_DIR="$E2E_LOG_DIR/benchmark"
else
  BENCH_DIR="$LOG_BASE/e2e/benchmark_$(date '+%Y-%m-%d_%H-%M-%S')"
fi
mkdir -p "$BENCH_DIR"

# -- Download tokenizer from model blob storage --------------------------------
TOKENIZER_DIR="$BENCH_DIR/tokenizer"
mkdir -p "$TOKENIZER_DIR"

info "Discovering model from deployment..."
FIRST_SKU="${SKUS[0]}"
FIRST_EP=$(sku_endpoint_name "$FIRST_SKU")

DEPLOYMENT_MODEL=$(az ml online-deployment show \
  --name "$DEPLOYMENT_NAME" \
  --endpoint-name "$FIRST_EP" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  --query model -o tsv)

info "Deployment model: $DEPLOYMENT_MODEL"

# Parse: azureml://registries/<reg>/models/<name>/versions/<ver>
PARSED_REG=$(echo "$DEPLOYMENT_MODEL" | sed 's|azureml://registries/\([^/]*\)/.*|\1|')
PARSED_MODEL=$(echo "$DEPLOYMENT_MODEL" | sed 's|.*/models/\([^/]*\)/.*|\1|')
PARSED_VER=$(echo "$DEPLOYMENT_MODEL" | sed 's|.*/versions/\(.*\)|\1|')

info "Resolved model: $PARSED_MODEL v$PARSED_VER (registry: $PARSED_REG)"

MODEL_BLOB_PATH=$(az ml model show \
  --name "$PARSED_MODEL" \
  --version "$PARSED_VER" \
  --registry-name "$PARSED_REG" \
  --query path -o tsv)

info "Model blob path: $MODEL_BLOB_PATH"

TOKENIZER_DOWNLOADED=false
STORAGE_TOKEN=$(az account get-access-token \
  --resource https://storage.azure.com/ \
  --query accessToken -o tsv 2>/dev/null || true)

if [[ -n "$STORAGE_TOKEN" ]]; then
  info "Listing model blob files..."
  BLOB_LIST_XML=$(curl -sS \
    "${MODEL_BLOB_PATH}?restype=container&comp=list" \
    -H "Authorization: Bearer $STORAGE_TOKEN" \
    -H "x-ms-version: 2020-04-08" 2>/dev/null || true)

  if echo "$BLOB_LIST_XML" | grep -q "<Name>"; then
    python3 -c "
import sys, xml.etree.ElementTree as ET
tree = ET.fromstring(sys.stdin.read())
for blob in tree.iter('Blob'):
    name = blob.find('Name').text
    size = blob.find('Properties/Content-Length').text
    print(f'  {name:50s}  {int(size):>15,} bytes')
" <<< "$BLOB_LIST_XML" 2>/dev/null || true

    TOKENIZER_FILE_LIST=("tokenizer.json" "tokenizer_config.json" "config.json" "vocab.json" "merges.txt")
    DL_COUNT=0
    for tfile in "${TOKENIZER_FILE_LIST[@]}"; do
      if echo "$BLOB_LIST_XML" | grep -q "<Name>${tfile}</Name>"; then
        HTTP_CODE=$(curl -sS -w "%{http_code}" -o "$TOKENIZER_DIR/$tfile" \
          "${MODEL_BLOB_PATH}/${tfile}" \
          -H "Authorization: Bearer $STORAGE_TOKEN" \
          -H "x-ms-version: 2020-04-08" 2>/dev/null)
        if [[ "$HTTP_CODE" == "200" ]]; then
          info "  Downloaded: $tfile ($(wc -c < "$TOKENIZER_DIR/$tfile" | tr -d ' ') bytes)"
          DL_COUNT=$((DL_COUNT + 1))
        else
          rm -f "$TOKENIZER_DIR/$tfile"
        fi
      fi
    done
    if [[ $DL_COUNT -gt 0 ]]; then
      TOKENIZER_DOWNLOADED=true
    fi
  else
    info "Could not list blobs via Storage API (may need Storage Blob Data Reader role)"
  fi
fi

if [[ "$TOKENIZER_DOWNLOADED" == true ]]; then
  TOKENIZER="$TOKENIZER_DIR"
  info "Using local tokenizer from model blob storage: $TOKENIZER_DIR"
else
  # Fallback: check for local model-artifacts directory
  if [[ -f "$MODEL_DIR/tokenizer.json" ]]; then
    TOKENIZER="$MODEL_DIR"
    info "Fallback: using local model-artifacts tokenizer at $TOKENIZER"
  else
    TOKENIZER="$HF_MODEL_ID"
    info "Fallback: using HuggingFace Hub tokenizer ($TOKENIZER)"
  fi
fi

info "Results will be saved to: $BENCH_DIR"

# -- Benchmark function for one GPU SKU --------------------------------------
bench_gpu() {
  local gpu="$1"
  local base_url api_key
  eval "base_url=\"\$BASE_URL_${gpu}\""
  eval "api_key=\"\$API_KEY_${gpu}\""

  local gpu_dir="$BENCH_DIR/$gpu"
  mkdir -p "$gpu_dir"

  local RUN=0
  local TOTAL=$(( ${#CONCURRENCIES[@]} * ${#TOKEN_CONFIGS[@]} ))

  for token_cfg in "${TOKEN_CONFIGS[@]}"; do
    read -r INPUT_TOKENS OUTPUT_TOKENS LABEL <<< "$token_cfg"

    for CONCURRENCY in "${CONCURRENCIES[@]}"; do
      RUN=$((RUN + 1))
      local RUN_NAME="c${CONCURRENCY}_in${INPUT_TOKENS}_out${OUTPUT_TOKENS}"
      local RUN_DIR="$gpu_dir/$RUN_NAME"
      mkdir -p "$RUN_DIR"

      info "[$gpu] [$RUN/$TOTAL] concurrency=$CONCURRENCY  input=$INPUT_TOKENS  output=$OUTPUT_TOKENS  ($LABEL)"

      aiperf profile \
        --model "$BENCH_MODEL" \
        --endpoint-type chat \
        --streaming \
        --tokenizer "$TOKENIZER" \
        --url "$base_url" \
        --header "Authorization: Bearer $api_key" \
        --concurrency "$CONCURRENCY" \
        --request-count "$REQUEST_COUNT" \
        --synthetic-input-tokens-mean "$INPUT_TOKENS" \
        --synthetic-input-tokens-stddev 0 \
        --output-tokens-mean "$OUTPUT_TOKENS" \
        --output-tokens-stddev 0 \
        --artifact-dir "$RUN_DIR" \
        --ui none \
        2>&1 | tee "$RUN_DIR/run.log"

      info "[$gpu]   -> Saved to $RUN_DIR"
    done
  done

  info "[$gpu] All $TOTAL benchmark runs complete."
}

# -- Run benchmarks in parallel across SKUs -----------------------------------
info "Starting benchmarks in parallel for: ${SKUS[*]}"

PIDS=()
for sku in "${SKUS[@]}"; do
  log_file="$BENCH_DIR/7-bench-${sku}.log"

  bench_gpu "$sku" > >(tee "$log_file") 2>&1 &
  PIDS+=($!)
done

BENCH_FAILED=0
for pid in "${PIDS[@]}"; do
  if ! wait "$pid"; then BENCH_FAILED=1; fi
done

if [[ "$BENCH_FAILED" -ne 0 ]]; then
  err "One or more benchmarks failed."
  exit 1
fi

info "All benchmark runs complete. Results in: $BENCH_DIR"

# -- Summary ------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "  BENCHMARK COMPLETE (${SKUS[*]}) -- model=$MODEL_NAME"
echo "======================================================================"
echo "  Results: $BENCH_DIR"
for sku in "${SKUS[@]}"; do
  echo "  ${sku}:    $BENCH_DIR/${sku}/"
done
echo "======================================================================"
echo "  Note: Plots are generated post-pipeline (works for partial runs too)."
echo "======================================================================"

_step_end
