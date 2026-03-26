#!/usr/bin/env bash
# Step 1 (REST API): Create vLLM environment in the Azure ML registry
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

TOKEN=$(az account get-access-token --query accessToken -o tsv)

info "Creating environment '$ENVIRONMENT_NAME' v$ENVIRONMENT_VERSION via REST API…"

RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
  "${REGISTRY_BASE}/environments/${ENVIRONMENT_NAME}/versions/${ENVIRONMENT_VERSION}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "properties": {
      "image": "'"$VLLM_IMAGE"'",
      "description": "vLLM OpenAI-compatible inference server for Qwen3.5 models",
      "tags": {
        "framework": "vllm",
        "model_family": "qwen3.5"
      },
      "osType": "Linux"
    }
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" =~ ^2 ]]; then
  info "Environment created (HTTP $HTTP_CODE)."
  echo "$BODY" | python3 -m json.tool
else
  echo "ERROR: HTTP $HTTP_CODE"
  echo "$BODY" | python3 -m json.tool
  exit 1
fi
