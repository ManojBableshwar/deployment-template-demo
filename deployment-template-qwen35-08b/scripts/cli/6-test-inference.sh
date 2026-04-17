#!/usr/bin/env bash
# Step 6: Test inference on each deployed endpoint (SKU-aware)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"

read -ra SKUS <<< "${E2E_SKUS:-a100 h100}"
_step_start "Step 6: Test inference (${SKUS[*]})"

sku_endpoint_name() {
  case "$1" in
    a100) echo "qwen35-ep-a100" ;;
    h100) echo "qwen35-ep-h100" ;;
  esac
}

test_endpoint() {
  local sku="$1"
  local ep_name
  ep_name=$(sku_endpoint_name "$sku")

  info "[$sku] Fetching credentials for $ep_name..."
  local SCORING_URI API_KEY BASE_URL CHAT_URL

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
  if [[ "$BASE_URL" == */v1 ]]; then
    CHAT_URL="${BASE_URL}/chat/completions"
  else
    CHAT_URL="${BASE_URL}/v1/chat/completions"
  fi

  info "[$sku] URL: $CHAT_URL"
  info "[$sku] Sending chat completion request..."

  curl -sS -X POST "$CHAT_URL" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "model",
      "messages": [
        {"role": "user", "content": "Give me a short introduction to large language models."}
      ],
      "max_tokens": 512,
      "temperature": 1.0,
      "top_p": 1.0
    }' | python3 -m json.tool

  echo
  info "[$sku] Test complete."
}

for sku in "${SKUS[@]}"; do
  log_file="${E2E_LOG_DIR:-/tmp}/6-inference-${sku}.log"
  test_endpoint "$sku" 2>&1 | tee "$log_file"
done

_step_end
