#!/usr/bin/env bash
# Step 6 (REST API): Test the online deployment with chat completion
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

TOKEN=$(az account get-access-token --query accessToken -o tsv)

# Get the scoring URI
info "Fetching endpoint details…"
ENDPOINT_JSON=$(curl -s \
  "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN")

SCORING_URI=$(echo "$ENDPOINT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['properties']['scoringUri'])")

# Get the endpoint key
KEYS_JSON=$(curl -s -X POST \
  "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}/listKeys?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Length: 0")

ENDPOINT_KEY=$(echo "$KEYS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['primaryKey'])")

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
