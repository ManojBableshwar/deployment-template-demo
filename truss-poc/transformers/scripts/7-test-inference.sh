#!/usr/bin/env bash
# ==============================================================================
# 7-test-inference.sh -- Send test inference requests and verify responses
#
# Tests:
#   1. Truss native endpoint: POST /v1/models/model:predict
#   2. OpenAI-compatible endpoint: POST /v1/chat/completions
#   3. Health check: GET / (liveness)
#   4. Model readiness: GET /v1/models/model
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 7: Test Inference ==="

az account set --subscription "$SUBSCRIPTION_ID"

# -- Get endpoint scoring URI and key ------------------------------------------
SCORING_URI=$(az ml online-endpoint show \
  --name "$TRUSS_ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  --query "scoring_uri" -o tsv)

SCORING_KEY=$(az ml online-endpoint get-credentials \
  --name "$TRUSS_ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  --query "primaryKey" -o tsv)

if [[ -z "$SCORING_URI" || -z "$SCORING_KEY" ]]; then
  err "Could not retrieve scoring URI or key"
  exit 1
fi

info "Scoring URI: $SCORING_URI"
BASE_URI="${SCORING_URI%/}"

# -- Test 1: Liveness (GET /) --------------------------------------------------
info "Test 1: Liveness probe (GET /)"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $SCORING_KEY" \
  "$BASE_URI/")
if [[ "$HTTP_CODE" == "200" ]]; then
  ok "Liveness: HTTP $HTTP_CODE"
else
  warn "Liveness: HTTP $HTTP_CODE (expected 200)"
fi
echo "  HTTP $HTTP_CODE" >> "$LOG_DIR/7-test-inference.log"

# -- Test 2: Readiness (GET /v1/models/model) ----------------------------------
info "Test 2: Readiness probe (GET /v1/models/model)"
READINESS_RESPONSE=$(curl -s \
  -H "Authorization: Bearer $SCORING_KEY" \
  "$BASE_URI/v1/models/model")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $SCORING_KEY" \
  "$BASE_URI/v1/models/model")
if [[ "$HTTP_CODE" == "200" ]]; then
  ok "Readiness: HTTP $HTTP_CODE"
  echo "  Response: $READINESS_RESPONSE"
else
  warn "Readiness: HTTP $HTTP_CODE"
  echo "  Response: $READINESS_RESPONSE"
fi
echo "$READINESS_RESPONSE" > "$LOG_DIR/7-readiness-response.json"

# -- Test 3: Truss native predict (POST /v1/models/model:predict) ---------------
info "Test 3: Truss native predict"
PREDICT_REQUEST='{"prompt": "What is the capital of France?", "max_new_tokens": 50, "temperature": 0.1}'
info "Request: $PREDICT_REQUEST"

PREDICT_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $SCORING_KEY" \
  -H "Content-Type: application/json" \
  -d "$PREDICT_REQUEST" \
  "$BASE_URI/v1/models/model:predict")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -H "Authorization: Bearer $SCORING_KEY" \
  -H "Content-Type: application/json" \
  -d "$PREDICT_REQUEST" \
  "$BASE_URI/v1/models/model:predict")

if [[ "$HTTP_CODE" == "200" ]]; then
  ok "Truss predict: HTTP $HTTP_CODE"
  echo "  Response: $PREDICT_RESPONSE"
else
  err "Truss predict: HTTP $HTTP_CODE"
  echo "  Response: $PREDICT_RESPONSE"
fi
echo "$PREDICT_RESPONSE" > "$LOG_DIR/7-predict-response.json"

# -- Test 4: OpenAI chat completions (POST /v1/chat/completions) ---------------
info "Test 4: OpenAI-compatible chat completions"
CHAT_REQUEST='{
  "model": "model",
  "messages": [{"role": "user", "content": "Say hello in one word."}],
  "max_tokens": 20,
  "temperature": 0.1
}'
info "Request: $CHAT_REQUEST"

CHAT_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $SCORING_KEY" \
  -H "Content-Type: application/json" \
  -d "$CHAT_REQUEST" \
  "$BASE_URI/v1/chat/completions")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -H "Authorization: Bearer $SCORING_KEY" \
  -H "Content-Type: application/json" \
  -d "$CHAT_REQUEST" \
  "$BASE_URI/v1/chat/completions")

if [[ "$HTTP_CODE" == "200" ]]; then
  ok "Chat completions: HTTP $HTTP_CODE"
  echo "  Response: $CHAT_RESPONSE"
else
  warn "Chat completions: HTTP $HTTP_CODE (may not be implemented in basic Truss model)"
  echo "  Response: $CHAT_RESPONSE"
fi
echo "$CHAT_RESPONSE" > "$LOG_DIR/7-chat-response.json"

# -- Summary -------------------------------------------------------------------
info "=== Test Summary ==="
echo "  Liveness (GET /):                    tested"
echo "  Readiness (GET /v1/models/model):    tested"
echo "  Predict (POST /v1/models/model:predict): tested"
echo "  Chat (POST /v1/chat/completions):    tested"
echo ""
echo "  Logs: $LOG_DIR/"
