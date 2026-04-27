#!/usr/bin/env bash
# Step 2: Create deployment templates in the Azure ML registry (one per TP value)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"

read -ra TPS <<< "${E2E_TPS:-1}"
read -ra SKUS <<< "${E2E_SKUS:-a100 h100}"
_step_start "Step 2: Create deployment templates (TP=${TPS[*]})"

CALC_SCRIPT="$SCRIPT_DIR/../calc-vllm-config.sh"

if [[ ! -f "$MODEL_CONFIG" ]]; then
  echo "[ERROR] config.json not found at $MODEL_CONFIG" >&2
  echo "  Step 0 should have downloaded model artifacts. Re-run from step 0." >&2
  exit 1
fi

# -- Auto-detect tool-call parser (shared across all TPs) --------------------
if [[ -z "${VLLM_TOOL_CALL_PARSER:-}" ]]; then
  _model_dir="$(dirname "$MODEL_CONFIG")"
  _tok_config="$_model_dir/tokenizer_config.json"
  _jinja_file="$_model_dir/chat_template.jinja"
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
    info "Auto-detected VLLM_TOOL_CALL_PARSER=${VLLM_TOOL_CALL_PARSER:-<none>}"
  else
    VLLM_TOOL_CALL_PARSER=""
    info "No chat_template found — skipping tool-call parser detection"
  fi
else
  info "VLLM_TOOL_CALL_PARSER=${VLLM_TOOL_CALL_PARSER} (from config.sh override)"
fi
export VLLM_TOOL_CALL_PARSER

# -- Loop over each TP value --------------------------------------------------
FIRST_TP=true
for tp in "${TPS[@]}"; do
  info "────────────────────────────────────────────────"
  info "Processing TP=$tp"

  local_dt_name=$(tp_template_name "$tp")
  local_inst_type=$(tp_to_instance_type "$tp" "h100")
  DT_FILE="$YAML_DIR/deployment-template-tp${tp}.yml"

  # Compute vLLM config for this TP
  if [[ -f "$CALC_SCRIPT" && -f "$DT_FILE" ]]; then
    CALC_ARGS=(--config "$MODEL_CONFIG")
    CALC_ARGS+=(--sku "$local_inst_type")
    CALC_ARGS+=(--tp "$tp")

    info "Computing vLLM config for TP=$tp: calc-vllm-config.sh ${CALC_ARGS[*]:-}"
    eval "$("$CALC_SCRIPT" "${CALC_ARGS[@]}" --export)"

    info "  TP=$tp: VLLM_TENSOR_PARALLEL_SIZE=$VLLM_TENSOR_PARALLEL_SIZE"
    info "  TP=$tp: VLLM_MAX_MODEL_LEN=$VLLM_MAX_MODEL_LEN"
    info "  TP=$tp: VLLM_GPU_MEMORY_UTILIZATION=$VLLM_GPU_MEMORY_UTILIZATION"
    info "  TP=$tp: VLLM_MAX_NUM_SEQS=$VLLM_MAX_NUM_SEQS"
    info "  TP=$tp: BENCHMARK_CONCURRENCIES=$BENCHMARK_CONCURRENCIES"

    # Hydrate VLLM_* values into the DT YAML
    _vllm_sed_args=(
      -e "s|\${VLLM_TENSOR_PARALLEL_SIZE}|${VLLM_TENSOR_PARALLEL_SIZE}|g"
      -e "s|\${VLLM_MAX_MODEL_LEN}|${VLLM_MAX_MODEL_LEN}|g"
      -e "s|\${VLLM_GPU_MEMORY_UTILIZATION}|${VLLM_GPU_MEMORY_UTILIZATION}|g"
      -e "s|\${VLLM_MAX_NUM_SEQS}|${VLLM_MAX_NUM_SEQS}|g"
      -e "s|\${VLLM_TOOL_CALL_PARSER}|${VLLM_TOOL_CALL_PARSER:-}|g"
    )

    _tmp=$(mktemp)
    sed "${_vllm_sed_args[@]}" "$DT_FILE" > "$_tmp"
    mv "$_tmp" "$DT_FILE"
    info "Hydrated VLLM config into deployment-template-tp${tp}.yml"

    # Hydrate VLLM_* into per-TP×SKU deployment YAMLs
    for sku in "${SKUS[@]}"; do
      dep_yaml="$YAML_DIR/deployment-tp${tp}-${sku}.yml"
      if [[ -f "$dep_yaml" ]]; then
        _tmp=$(mktemp)
        sed "${_vllm_sed_args[@]}" "$dep_yaml" > "$_tmp"
        mv "$_tmp" "$dep_yaml"
        info "Hydrated VLLM env vars into deployment-tp${tp}-${sku}.yml"
      fi
    done

    # For the first TP, also generate benchmark-config.yml with per-token-config concurrencies
    if [[ "$FIRST_TP" == "true" ]]; then
      BENCH_CFG_TMPL="$YAML_DIR/benchmark-config.yml"
      python3 -c "
import math

max_kv_tokens = $BENCHMARK_MAX_KV_TOKENS
max_num_seqs  = $VLLM_MAX_NUM_SEQS
model_name    = '$MODEL_NAME'

token_configs = [
    (200,  800,  'short-gen'),
    (800,  200,  'short-prompt'),
    (2000, 8000, 'long-gen'),
    (8000, 2000, 'long-prompt'),
]

def calc_concurrencies(max_batch, max_num_seqs):
    # Effective limit: KV cache vs vLLM batch setting, whichever is tighter
    effective = min(max_batch, max_num_seqs)
    concs = []
    c = 1
    while c <= effective * 1.5:
        if c >= 2:
            concs.append(c)
        c *= 2
    if effective >= 2 and effective not in concs:
        concs.append(effective)
    boundary = int(effective * 1.5)
    if boundary >= 2 and boundary not in concs:
        concs.append(boundary)
    return sorted(set(concs))

lines = [
    f'# Benchmark configuration for {model_name}',
    '# Auto-generated by step 2 (create-deployment-template) using calc-vllm-config.sh',
    '#',
    '# Concurrency levels are per token-config based on KV cache capacity.',
    f'# max_kv_tokens={max_kv_tokens}  max_num_seqs={max_num_seqs}',
    '',
    'benchmark:',
    '  request_count: 100',
    f'  max_num_seqs: {max_num_seqs}',
    f'  max_kv_tokens: {max_kv_tokens}',
    '',
    '  token_configs:',
]

for inp, out, label in token_configs:
    total = inp + out
    max_batch = min(max_kv_tokens // total, 256)
    concs = calc_concurrencies(max_batch, max_num_seqs)
    conc_str = ', '.join(str(c) for c in concs)
    lines.append(f'    - input: {inp}')
    lines.append(f'      output: {out}')
    lines.append(f'      label: \"{label}\"')
    lines.append(f'      max_batch: {max_batch}')
    lines.append(f'      concurrencies: [{conc_str}]')

with open('$BENCH_CFG_TMPL', 'w') as f:
    f.write('\n'.join(lines) + '\n')

# Print summary for logging
for inp, out, label in token_configs:
    total = inp + out
    max_batch = min(max_kv_tokens // total, 256)
    concs = calc_concurrencies(max_batch, max_num_seqs)
    print(f'  {label:14s} (in={inp:>5} out={out:>5} total={total:>6}): max_batch={max_batch:>4}  concs={concs}')
"
      info "Generated benchmark-config.yml with per-token-config concurrencies (max_kv_tokens=$BENCHMARK_MAX_KV_TOKENS)"
      FIRST_TP=false
    fi
  else
    info "No calc script or DT template found for TP=$tp — skipping vLLM config computation."
  fi

  # Create or skip the deployment template in the registry
  if az ml deployment-template show --name "$local_dt_name" --version "$TEMPLATE_VERSION" --registry-name "$AZUREML_REGISTRY" >/dev/null 2>&1; then
    info "Deployment template '$local_dt_name' v$TEMPLATE_VERSION already exists -- skipping creation."
  else
    info "Creating deployment template '$local_dt_name' v$TEMPLATE_VERSION in registry '$AZUREML_REGISTRY'..."
    az ml deployment-template create \
      --file "$DT_FILE" \
      --registry-name "$AZUREML_REGISTRY"
    info "Deployment template '$local_dt_name' created."
  fi

  info "Showing details:"
  az ml deployment-template show \
    --name "$local_dt_name" \
    --version "$TEMPLATE_VERSION" \
    --registry-name "$AZUREML_REGISTRY" \
    -o json
done

_step_end
