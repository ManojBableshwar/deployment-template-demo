#!/usr/bin/env bash
# Step 2: Create deployment template in the Azure ML registry
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"
_step_start "Step 2: Create deployment template"

# ── Compute vLLM config from model metadata ──────────────────────────────────
CALC_SCRIPT="$SCRIPT_DIR/../calc-vllm-config.sh"
TMPL_FILE="$YAML_DIR/deployment-template.yml"
GENERATED_FILE="$YAML_DIR/deployment-template.yml"

if [[ ! -f "$MODEL_CONFIG" ]]; then
  echo "[ERROR] config.json not found at $MODEL_CONFIG" >&2
  echo "  Step 0 should have downloaded model artifacts. Re-run from step 0." >&2
  exit 1
fi

if [[ -f "$CALC_SCRIPT" && -f "$TMPL_FILE" ]]; then
  CALC_ARGS=(--config "$MODEL_CONFIG")
  # Use H100 SKU as the reference for DT vLLM settings (default_instance_type)
  CALC_ARGS+=(--sku "${INSTANCE_TYPE_H100}")
  [[ -n "${E2E_SKU:-}" ]]       && CALC_ARGS+=(--sku "$E2E_SKU")
  [[ -n "${E2E_GPU:-}" ]]       && CALC_ARGS+=(--gpu "$E2E_GPU")
  [[ -n "${E2E_TP:-}" ]]        && CALC_ARGS+=(--tp "$E2E_TP")

  info "Computing vLLM config: calc-vllm-config.sh ${CALC_ARGS[*]:-}"
  eval "$("$CALC_SCRIPT" "${CALC_ARGS[@]}" --export)"

  info "  VLLM_TENSOR_PARALLEL_SIZE=$VLLM_TENSOR_PARALLEL_SIZE"
  info "  VLLM_MAX_MODEL_LEN=$VLLM_MAX_MODEL_LEN"
  info "  VLLM_GPU_MEMORY_UTILIZATION=$VLLM_GPU_MEMORY_UTILIZATION"
  info "  VLLM_MAX_NUM_SEQS=$VLLM_MAX_NUM_SEQS"
  info "  BENCHMARK_CONCURRENCIES=$BENCHMARK_CONCURRENCIES"

  # Auto-detect tool-call parser from chat_template (unless already set)
  if [[ -z "${VLLM_TOOL_CALL_PARSER:-}" ]]; then
    _model_dir="$(dirname "$MODEL_CONFIG")"
    _tok_config="$_model_dir/tokenizer_config.json"
    _jinja_file="$_model_dir/chat_template.jinja"
    # Try tokenizer_config.json first, fall back to chat_template.jinja
    _chat_tmpl=""
    if [[ -f "$_tok_config" ]]; then
      _chat_tmpl=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); ct=d.get('chat_template',''); print(ct if isinstance(ct,str) else '')" "$_tok_config" 2>/dev/null || true)
    fi
    if [[ -z "$_chat_tmpl" && -f "$_jinja_file" ]]; then
      _chat_tmpl=$(cat "$_jinja_file")
    fi
    if [[ -n "$_chat_tmpl" ]]; then
      if echo "$_chat_tmpl" | grep -qE '<\|tool_call\|>|<\|tool_call>|tool_call\|>'; then
        VLLM_TOOL_CALL_PARSER="gemma4"
      elif echo "$_chat_tmpl" | grep -q '<tool_call>'; then
        VLLM_TOOL_CALL_PARSER="hermes"
      elif echo "$_chat_tmpl" | grep -q '<|python_tag|>'; then
        VLLM_TOOL_CALL_PARSER="llama3_json"
      elif echo "$_chat_tmpl" | grep -q '\[TOOL_CALLS\]'; then
        VLLM_TOOL_CALL_PARSER="mistral"
      else
        VLLM_TOOL_CALL_PARSER=""
      fi
      info "  Auto-detected VLLM_TOOL_CALL_PARSER=${VLLM_TOOL_CALL_PARSER:-<none>}"
    else
      VLLM_TOOL_CALL_PARSER=""
      info "  No chat_template found — skipping tool-call parser detection"
    fi
  else
    info "  VLLM_TOOL_CALL_PARSER=${VLLM_TOOL_CALL_PARSER} (from config.sh override)"
  fi
  export VLLM_TOOL_CALL_PARSER

  # Second-pass hydration: fill in VLLM_* values (resource names already set by hydrate_yaml)
  _tmp=$(mktemp)
  _vllm_sed_args=(
    -e "s|\${VLLM_TENSOR_PARALLEL_SIZE}|${VLLM_TENSOR_PARALLEL_SIZE}|g"
    -e "s|\${VLLM_MAX_MODEL_LEN}|${VLLM_MAX_MODEL_LEN}|g"
    -e "s|\${VLLM_GPU_MEMORY_UTILIZATION}|${VLLM_GPU_MEMORY_UTILIZATION}|g"
    -e "s|\${VLLM_MAX_NUM_SEQS}|${VLLM_MAX_NUM_SEQS}|g"
    -e "s|\${VLLM_TOOL_CALL_PARSER}|${VLLM_TOOL_CALL_PARSER:-}|g"
  )
  sed "${_vllm_sed_args[@]}" "$TMPL_FILE" > "$_tmp"
  mv "$_tmp" "$GENERATED_FILE"
  info "Hydrated VLLM config into deployment-template.yml."

  # Also hydrate VLLM_* values into deployment YAMLs (workaround: DT env vars don't propagate)
  for dep_yaml in "$YAML_DIR"/deployment-*.yml; do
    [[ -f "$dep_yaml" ]] || continue
    _tmp=$(mktemp)
    sed "${_vllm_sed_args[@]}" "$dep_yaml" > "$_tmp"
    mv "$_tmp" "$dep_yaml"
    info "Hydrated VLLM env vars into $(basename "$dep_yaml")."
  done

  # Hydrate benchmark-config.yml with calculated concurrencies
  BENCH_CFG_TMPL="$YAML_DIR/benchmark-config.yml"
  if [[ -f "$BENCH_CFG_TMPL" ]]; then
    # Convert space-separated "2 4 8 16" → YAML inline array "2, 4, 8, 16"
    _bench_conc_yaml=$(echo "$BENCHMARK_CONCURRENCIES" | tr ' ' ',' | sed 's/,/, /g')
    _tmp=$(mktemp)
    sed \
      -e "s|\${BENCHMARK_CONCURRENCIES}|${_bench_conc_yaml}|g" \
      -e "s|\${VLLM_MAX_NUM_SEQS}|${VLLM_MAX_NUM_SEQS}|g" \
      -e "s|\${MODEL_NAME}|${MODEL_NAME}|g" \
      "$BENCH_CFG_TMPL" > "$_tmp"
    mv "$_tmp" "$BENCH_CFG_TMPL"
    info "Hydrated benchmark-config.yml: concurrencies=[${_bench_conc_yaml}]  max_num_seqs=$VLLM_MAX_NUM_SEQS"
  fi
else
  info "No calc script or template found — using deployment-template.yml as-is."
fi

# Check if deployment template already exists
if az ml deployment-template show --name "$TEMPLATE_NAME" --version "$TEMPLATE_VERSION" --registry-name "$AZUREML_REGISTRY" 2>&1; then
  info "Deployment template '$TEMPLATE_NAME' v$TEMPLATE_VERSION already exists -- skipping creation."
else
  info "Creating deployment template '$TEMPLATE_NAME' v$TEMPLATE_VERSION in registry '$AZUREML_REGISTRY'..."
  az ml deployment-template create \
    --file "$GENERATED_FILE" \
    --registry-name "$AZUREML_REGISTRY"
  info "Deployment template created."
fi

info "Showing details:"
az ml deployment-template show \
  --name "$TEMPLATE_NAME" \
  --version "$TEMPLATE_VERSION" \
  --registry-name "$AZUREML_REGISTRY" \
  -o json

_step_end
