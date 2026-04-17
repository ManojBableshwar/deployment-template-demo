#!/usr/bin/env bash
# Step 6 (REST API): Test the online deployment with chat completion
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"
_step_start "Step 6: Test inference"

TOKEN=$(az account get-access-token --query accessToken -o tsv)

# Get the scoring URI via REST
info "Fetching endpoint details..."
ENDPOINT_JSON=$(curl -sS \
  "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN")

SCORING_URI=$(echo "$ENDPOINT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['properties']['scoringUri'])")

# Get the endpoint key via REST
KEYS_JSON=$(curl -sS -X POST \
  "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}/listKeys?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Length: 0")

ENDPOINT_KEY=$(echo "$KEYS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['primaryKey'])")

# Derive the chat completions URL
BASE_URL="${SCORING_URI%/score}"
BASE_URL="${BASE_URL%/}"

if [[ "$BASE_URL" == */v1 ]]; then
  CHAT_COMPLETIONS_URL="${BASE_URL}/chat/completions"
else
  CHAT_COMPLETIONS_URL="${BASE_URL}/v1/chat/completions"
fi

info "Scoring URI: $SCORING_URI"
info "Sending chat completion request..."

curl -sS -X POST "$CHAT_COMPLETIONS_URL" \
  -H "Authorization: Bearer $ENDPOINT_KEY" \
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
info "Test complete."

_step_end
