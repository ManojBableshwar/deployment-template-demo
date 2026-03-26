#!/usr/bin/env bash
# Step 4 (REST API): Create a managed online endpoint
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

TOKEN=$(az account get-access-token --query accessToken -o tsv)

info "Creating online endpoint '$ENDPOINT_NAME' via REST API…"

RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
  "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "location": "'"$WORKSPACE_LOCATION"'",
    "properties": {
      "authMode": "Key",
      "description": "Online endpoint for Qwen3.5-0.8B served via vLLM"
    }
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" =~ ^2 ]]; then
  info "Endpoint created (HTTP $HTTP_CODE)."
  echo "$BODY" | python3 -m json.tool
else
  echo "ERROR: HTTP $HTTP_CODE"
  echo "$BODY" | python3 -m json.tool
  exit 1
fi
