#!/usr/bin/env bash
# Step 6: Test inference via llm-api-spec (API compatibility verification)
# Runs llm-api-validate in --debug mode against each deployed endpoint.
# Generates a human-readable markdown report per TP×SKU under the log directory.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

# -- Pre-check: llm-api-validate must be installed ----------------------------
if ! command -v llm-api-validate &>/dev/null; then
  err "llm-api-validate not found. Install llm-api-spec:"
  err "  pip install -e /path/to/LLM-API-Spec"
  exit 1
fi

az account set --subscription "$SUBSCRIPTION_ID"

read -ra TPS <<< "${E2E_TPS:-1}"
read -ra SKUS <<< "${E2E_SKUS:-a100 h100}"
_step_start "Step 6: Test inference (TP=${TPS[*]} × SKU=${SKUS[*]})"

LOG_DIR="${E2E_LOG_DIR:-/tmp}"

test_endpoint() {
  local tp="$1" sku="$2"
  local ep_name
  ep_name=$(tp_sku_endpoint_name "$tp" "$sku")
  local label="tp${tp}-${sku}"

  info "[$label] Fetching credentials for $ep_name..."

  local SCORING_URI API_KEY BASE_URL

  SCORING_URI=$(az ml online-endpoint show \
    --name "$ep_name" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query scoring_uri -o tsv)

  API_KEY=$(az ml online-endpoint get-credentials \
    --name "$ep_name" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --query primaryKey -o tsv)

  BASE_URL="${SCORING_URI%/score}"
  BASE_URL="${BASE_URL%/}"
  # Ensure base URL ends with /v1
  if [[ "$BASE_URL" != */v1 ]]; then
    BASE_URL="${BASE_URL}/v1"
  fi

  info "[$label] Base URL: $BASE_URL"

  # -- Build runtime target config from template ------------------------------
  local target_tmpl="$YAML_DIR/llm-api-spec-target.yml"
  local target_runtime
  target_runtime=$(mktemp "${LOG_DIR}/6-target-${label}-XXXXX.yml")

  # Filter to just this endpoint's target block and inject runtime values
  # (API key and base URL are NOT in the template — injected here)
  python3 -c "
import yaml, sys

with open(sys.argv[1]) as f:
    cfg = yaml.safe_load(f)

ep_name = sys.argv[2]
base_url = sys.argv[3]
api_key = sys.argv[4]

# Filter to only the target matching this endpoint
filtered = [t for t in cfg.get('targets', []) if t['name'] == ep_name]
if not filtered:
    # Fallback: create inline target
    filtered = [{
        'name': ep_name,
        'base_url': base_url,
        'api_key': api_key,
        'model': 'model',
        'schemas': ['chat_completions'],
        'timeout': 120,
        'headers': {'Authorization': f'Bearer {api_key}'}
    }]
else:
    for t in filtered:
        t['base_url'] = base_url
        t['api_key'] = api_key
        t['headers'] = {'Authorization': f'Bearer {api_key}'}

yaml.dump({'targets': filtered}, sys.stdout, default_flow_style=False)
" "$target_tmpl" "$ep_name" "$BASE_URL" "$API_KEY" > "$target_runtime"

  info "[$label] Target config written to: $target_runtime"

  # -- Run llm-api-validate in debug mode -------------------------------------
  local md_report="${LOG_DIR}/6-inference-${label}.md"
  local json_report="${LOG_DIR}/6-inference-${label}.json"
  local debug_log="${LOG_DIR}/6-inference-${label}-debug.log"

  info "[$label] Running llm-api-validate --debug --schema chat_completions..."

  llm-api-validate \
    --config "$target_runtime" \
    --schema chat_completions \
    --debug \
    --output markdown \
    --output-file "$md_report" \
    --timeout 120 \
    2>"$debug_log" || true

  # Also generate JSON output for programmatic consumption
  llm-api-validate \
    --config "$target_runtime" \
    --schema chat_completions \
    --debug \
    --output json \
    --output-file "$json_report" \
    --timeout 120 \
    2>/dev/null || true

  # Clean up runtime config (contains API key)
  rm -f "$target_runtime"

  # -- Print summary to console -----------------------------------------------
  if [[ -f "$md_report" ]]; then
    info "[$label] Markdown report: $md_report"
    # Extract and show the summary line
    grep -E '^[^ ].*passed|^##' "$md_report" | head -5
    echo
  else
    err "[$label] No report generated — check $debug_log"
  fi

  if [[ -f "$json_report" ]]; then
    info "[$label] JSON report: $json_report"
    # Show pass/fail counts
    python3 -c "
import json
with open('$json_report') as f:
    data = json.load(f)
s = data.get('summary', {})
print(f\"  Total: {s.get('total',0)} | Passed: {s.get('passed',0)} | Failed: {s.get('failed',0)} | Unsupported: {s.get('unsupported',0)}\")
" 2>/dev/null || true
  fi
}

for tp in "${TPS[@]}"; do
  for sku in "${SKUS[@]}"; do
    label="tp${tp}-${sku}"
    log_file="${LOG_DIR}/6-inference-${label}.log"
    test_endpoint "$tp" "$sku" 2>&1 | tee "$log_file"
  done
done

_step_end
