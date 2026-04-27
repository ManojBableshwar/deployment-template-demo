#!/usr/bin/env bash
# Step 7: Benchmark deployments with AIPerf (TP×SKU-aware, parallel across combos)
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

read -ra TPS <<< "${E2E_TPS:-1}"
read -ra SKUS <<< "${E2E_SKUS:-a100 h100}"
_step_start "Step 7: Benchmark endpoint (TP=${TPS[*]} × SKU=${SKUS[*]})"

# Build TP×SKU combos
COMBOS=()
for tp in "${TPS[@]}"; do
  for sku in "${SKUS[@]}"; do
    COMBOS+=("${tp}:${sku}")
  done
done

# -- Fetch per-combo credentials -----------------------------------------------
# Use dynamic variable names instead of associative arrays (bash 3.2 compat)

for combo in "${COMBOS[@]}"; do
  tp="${combo%%:*}"
  sku="${combo##*:}"
  label="tp${tp}-${sku}"
  ep_name=$(tp_sku_endpoint_name "$tp" "$sku")

  info "[$label] Fetching credentials for $ep_name..."

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

  eval "_BASE_URL_${tp}_${sku}=\"\$base_url\""
  eval "_API_KEY_${tp}_${sku}=\"\$api_key\""

  info "[$label] Endpoint: $base_url"
done

# -- Benchmark config ---------------------------------------------------------
BENCH_CFG="$YAML_DIR/benchmark-config.yml"
REQUEST_COUNT=100

# Read token configs (with per-config concurrencies) from YAML.
# Supports both new format (per-config concurrencies) and old format (global concurrencies).
# Serialized as: TC:input:output:label:conc1 conc2 ...
TOKEN_CONFIGS=()

if [[ -f "$BENCH_CFG" ]] && python3 -c "import yaml" 2>/dev/null; then
  _TOKEN_CFG_DATA=$(python3 -c "
import yaml
with open('$BENCH_CFG') as f:
    cfg = yaml.safe_load(f)
bc = cfg.get('benchmark', {})
req = bc.get('request_count', 100)
print(f'REQUEST_COUNT={req}')
tcs = bc.get('token_configs', [])
global_concs = bc.get('concurrencies', [])
if tcs and isinstance(tcs[0], dict):
    # New format: per-config concurrencies
    for tc in tcs:
        concs = ' '.join(str(c) for c in tc.get('concurrencies', global_concs or [2,4,8,16,32,64]))
        print(f'TC:{tc[\"input\"]}:{tc[\"output\"]}:{tc[\"label\"]}:{concs}')
elif tcs and isinstance(tcs[0], list):
    # Old format: global concurrencies applied to all configs
    conc_str = ' '.join(str(c) for c in global_concs) if global_concs else '2 4 8 16 24 48 96'
    for tc in tcs:
        print(f'TC:{tc[0]}:{tc[1]}:{tc[2]}:{conc_str}')
else:
    # No token configs — use defaults
    for inp, out, label in [(200,800,'short-gen'),(800,200,'short-prompt'),(2000,8000,'long-gen'),(8000,2000,'long-prompt')]:
        conc_str = ' '.join(str(c) for c in global_concs) if global_concs else '2 4 8 16 24 48 96'
        print(f'TC:{inp}:{out}:{label}:{conc_str}')
" 2>/dev/null || true)

  while IFS= read -r _line; do
    case "$_line" in
      REQUEST_COUNT=*) REQUEST_COUNT="${_line#*=}" ;;
      TC:*) TOKEN_CONFIGS+=("${_line#TC:}") ;;
    esac
  done <<< "$_TOKEN_CFG_DATA"
fi

# Fallback if YAML parsing failed or file missing
if [[ ${#TOKEN_CONFIGS[@]} -eq 0 ]]; then
  info "No token configs from YAML — using defaults with safe concurrencies"
  TOKEN_CONFIGS=(
    "200:800:short-gen:2 4 8 16 24 48 96"
    "800:200:short-prompt:2 4 8 16 24 48 96"
    "2000:8000:long-gen:2 4 8 16 24 48 96"
    "8000:2000:long-prompt:2 4 8 16 24 48 96"
  )
fi

# Log what we're about to run
info "Benchmark config: REQUEST_COUNT=$REQUEST_COUNT"
TOTAL_RUNS=0
for _tc in "${TOKEN_CONFIGS[@]}"; do
  IFS=: read -r _in _out _label _concs <<< "$_tc"
  read -ra _carr <<< "$_concs"
  _n=${#_carr[@]}
  TOTAL_RUNS=$(( TOTAL_RUNS + _n ))
  if [[ $_n -eq 0 ]]; then
    info "  $_label (in=$_in out=$_out): SKIPPED (no concurrency levels)"
  else
    info "  $_label (in=$_in out=$_out): ${_n} concurrency levels [${_carr[0]}..${_carr[${#_carr[@]}-1]}]"
  fi
done
info "Total benchmark runs per combo: $TOTAL_RUNS"

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
FIRST_COMBO="${COMBOS[0]}"
FIRST_TP="${FIRST_COMBO%%:*}"
FIRST_SKU="${FIRST_COMBO##*:}"
FIRST_EP=$(tp_sku_endpoint_name "$FIRST_TP" "$FIRST_SKU")
FIRST_DEP=$(tp_sku_deployment_name "$FIRST_TP")

DEPLOYMENT_MODEL=$(az ml online-deployment show \
  --name "$FIRST_DEP" \
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

# -- Benchmark function for one TP×SKU combo ----------------------------------
bench_combo() {
  local combo="$1"
  local tp="${combo%%:*}"
  local sku="${combo##*:}"
  local label="tp${tp}-${sku}"
  local base_url; eval "base_url=\$_BASE_URL_${tp}_${sku}"
  local api_key; eval "api_key=\$_API_KEY_${tp}_${sku}"

  local combo_dir="$BENCH_DIR/$label"
  mkdir -p "$combo_dir"

  local RUN=0

  for token_cfg in "${TOKEN_CONFIGS[@]}"; do
    local _tc_in _tc_out _tc_label _tc_concs_str
    IFS=: read -r _tc_in _tc_out _tc_label _tc_concs_str <<< "$token_cfg"
    local -a _tc_concs
    read -ra _tc_concs <<< "$_tc_concs_str"

    # Skip token configs with no concurrency levels
    if [[ ${#_tc_concs[@]} -eq 0 ]]; then
      info "[$label] Skipping $_tc_label (no concurrency levels configured)"
      continue
    fi

    # Ensure request_count >= max concurrency for this token config
    local _rc=$REQUEST_COUNT
    for c in "${_tc_concs[@]}"; do (( c > _rc )) && _rc=$c; done

    for CONCURRENCY in "${_tc_concs[@]}"; do
      RUN=$((RUN + 1))
      local RUN_NAME="c${CONCURRENCY}_in${_tc_in}_out${_tc_out}"
      local RUN_DIR="$combo_dir/$RUN_NAME"
      mkdir -p "$RUN_DIR"

      info "[$label] [$RUN/$TOTAL_RUNS] concurrency=$CONCURRENCY  input=$_tc_in  output=$_tc_out  ($_tc_label)"

      # Compute per-run timeout: generous estimate based on request count and token sizes
      # Base: ~10s per request at low concurrency, less at higher concurrency
      # Minimum 120s, maximum 600s (10 min)
      local _timeout=$(( (_rc * (_tc_in + _tc_out) / 500) + 120 ))
      (( _timeout > 600 )) && _timeout=600

      # Run aiperf with timeout to prevent indefinite hangs
      # NOTE: redirect to file instead of piping to tee so that $! captures
      # the aiperf PID (not the tee PID). This ensures kill -9 actually kills
      # aiperf on timeout, preventing orphaned processes.
      local _aiperf_pid
      aiperf profile \
        --model "$BENCH_MODEL" \
        --endpoint-type chat \
        --streaming \
        --tokenizer "$TOKENIZER" \
        --url "$base_url" \
        --header "Authorization: Bearer $api_key" \
        --concurrency "$CONCURRENCY" \
        --request-count "$_rc" \
        --synthetic-input-tokens-mean "$_tc_in" \
        --synthetic-input-tokens-stddev 0 \
        --output-tokens-mean "$_tc_out" \
        --output-tokens-stddev 0 \
        --artifact-dir "$RUN_DIR" \
        --ui none \
        > "$RUN_DIR/run.log" 2>&1 &
      _aiperf_pid=$!

      # Wait with timeout
      local _elapsed=0
      while kill -0 "$_aiperf_pid" 2>/dev/null; do
        sleep 5
        _elapsed=$((_elapsed + 5))
        if (( _elapsed >= _timeout )); then
          err "[$label] TIMEOUT after ${_timeout}s on $RUN_NAME — killing aiperf"
          kill -9 "$_aiperf_pid" 2>/dev/null || true
          wait "$_aiperf_pid" 2>/dev/null || true
          echo "TIMEOUT after ${_timeout}s" >> "$RUN_DIR/run.log"
          break
        fi
      done
      wait "$_aiperf_pid" 2>/dev/null || true
      # Show results summary from log
      grep -E "Benchmark Duration|TIMEOUT" "$RUN_DIR/run.log" 2>/dev/null || true

      info "[$label]   -> Saved to $RUN_DIR"
    done
  done

  info "[$label] All $TOTAL_RUNS benchmark runs complete."
}

# -- Run benchmarks in parallel across TP×SKU combos --------------------------
info "Starting benchmarks in parallel for: ${COMBOS[*]}"

PIDS=()
for combo in "${COMBOS[@]}"; do
  tp="${combo%%:*}"
  sku="${combo##*:}"
  label="tp${tp}-${sku}"
  log_file="$BENCH_DIR/7-bench-${label}.log"

  bench_combo "$combo" > >(tee "$log_file") 2>&1 &
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
echo "  BENCHMARK COMPLETE (${COMBOS[*]}) -- model=$MODEL_NAME"
echo "======================================================================"
echo "  Results: $BENCH_DIR"
for combo in "${COMBOS[@]}"; do
  tp="${combo%%:*}"
  sku="${combo##*:}"
  label="tp${tp}-${sku}"
  echo "  ${label}:    $BENCH_DIR/${label}/"
done
echo "======================================================================"
echo "  Note: Plots are generated post-pipeline (works for partial runs too)."
echo "======================================================================"

_step_end
