#!/usr/bin/env bash
# Step 6: Test the online deployment with a chat completion request
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"
_step_start "Step 6: Test inference"

# Get scoring URI and key
SCORING_URI=$(az ml online-endpoint show \
  --name "$ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  --query scoring_uri -o tsv)

ENDPOINT_KEY=$(az ml online-endpoint get-credentials \
  --name "$ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  --query primaryKey -o tsv)

# Derive the base URL (strip trailing /score if present)
BASE_URL="${SCORING_URI%/score}"

info "Scoring URI: $SCORING_URI"
info "Sending chat completion request…"

curl -s -X POST "${BASE_URL}/v1/chat/completions" \
  -H "Authorization: Bearer $ENDPOINT_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.5-0.8B",
    "messages": [
      {"role": "user", "content": "Give me a short introduction to large language models."}
    ],
    "max_tokens": 512,
    "temperature": 1.0,
    "top_p": 1.0
  }' | python3 -m json.tool

echo
info "Test complete."

_step_end
