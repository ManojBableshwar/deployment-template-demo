#!/usr/bin/env bash
# ==============================================================================
# 7-test-inference.sh -- Test the Truss+vLLM endpoint
#
# Unlike the transformers sample, /v1/chat/completions works NATIVELY here
# (vLLM serves it; Truss nginx passes it through). Tests:
#   1. Liveness         GET  /                         (nginx -> vLLM /health)
#   2. Readiness        GET  /v1/models/model          (nginx -> vLLM /health)
#   3. Truss predict    POST /v1/models/model:predict  (nginx -> /v1/chat/completions)
#   4. OpenAI chat      POST /v1/chat/completions       (passthrough, native)
#   5. OpenAI models    GET  /v1/models                 (passthrough, native)
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Step 7: Test Inference (Truss + vLLM) ==="
az account set --subscription "$SUBSCRIPTION_ID"

SCORING_URI=$(az ml online-endpoint show --name "$TRUSS_ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" \
  --query "scoring_uri" -o tsv)
SCORING_KEY=$(az ml online-endpoint get-credentials --name "$TRUSS_ENDPOINT_NAME" \
  --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" \
  --query "primaryKey" -o tsv)

if [[ -z "$SCORING_URI" || -z "$SCORING_KEY" ]]; then
  err "Could not retrieve scoring URI or key"; exit 1
fi
# AzureML scoring_uri ends in /score; strip it to reach the container root.
BASE_URI="${SCORING_URI%/score}"
info "Base URI: $BASE_URI"

AUTH=(-H "Authorization: Bearer $SCORING_KEY")
JSON=(-H "Content-Type: application/json")

# -- Test 1: Liveness ----------------------------------------------------------
info "Test 1: Liveness (GET /)"
code=$(curl -s -o /dev/null -w "%{http_code}" "${AUTH[@]}" "$BASE_URI/")
[[ "$code" == "200" ]] && ok "Liveness: HTTP $code" || warn "Liveness: HTTP $code (expected 200)"

# -- Test 2: Readiness ---------------------------------------------------------
info "Test 2: Readiness (GET /v1/models/model)"
code=$(curl -s -o /dev/null -w "%{http_code}" "${AUTH[@]}" "$BASE_URI/v1/models/model")
[[ "$code" == "200" ]] && ok "Readiness: HTTP $code" || warn "Readiness: HTTP $code"

# -- Test 3: Truss native predict ----------------------------------------------
info "Test 3: Truss predict (POST /v1/models/model:predict)"
REQ='{"model":"model","messages":[{"role":"user","content":"The capital of France is"}],"max_tokens":15,"temperature":0.1}'
RESP=$(curl -s -X POST "${AUTH[@]}" "${JSON[@]}" -d "$REQ" "$BASE_URI/v1/models/model:predict")
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${AUTH[@]}" "${JSON[@]}" -d "$REQ" "$BASE_URI/v1/models/model:predict")
echo "$RESP" > "$LOG_DIR/7-predict-response.json"
[[ "$code" == "200" ]] && ok "Truss predict: HTTP $code" || warn "Truss predict: HTTP $code"
echo "  $RESP" | head -c 400; echo

# -- Test 4: OpenAI chat completions (native passthrough) ----------------------
info "Test 4: OpenAI chat completions (POST /v1/chat/completions)"
RESP=$(curl -s -X POST "${AUTH[@]}" "${JSON[@]}" -d "$REQ" "$BASE_URI/v1/chat/completions")
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${AUTH[@]}" "${JSON[@]}" -d "$REQ" "$BASE_URI/v1/chat/completions")
echo "$RESP" > "$LOG_DIR/7-chat-response.json"
[[ "$code" == "200" ]] && ok "Chat completions: HTTP $code (NATIVE — vLLM serves it)" || warn "Chat completions: HTTP $code"
echo "  $RESP" | head -c 400; echo

# -- Test 5: OpenAI models list ------------------------------------------------
info "Test 5: OpenAI models list (GET /v1/models)"
RESP=$(curl -s "${AUTH[@]}" "$BASE_URI/v1/models")
code=$(curl -s -o /dev/null -w "%{http_code}" "${AUTH[@]}" "$BASE_URI/v1/models")
[[ "$code" == "200" ]] && ok "Models list: HTTP $code" || warn "Models list: HTTP $code"
echo "  $RESP" | head -c 300; echo

info "=== Test summary logged to: $LOG_DIR/ ==="
