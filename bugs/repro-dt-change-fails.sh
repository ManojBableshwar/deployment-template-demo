#!/usr/bin/env bash
# ==============================================================================
# repro-dt-change-fails.sh
#
# Reproduces the bug: changing an existing defaultDeploymentTemplate on a model
# in a registry fails with 404 / Invalid containerUri.
#
# Runs all 7 test cases from dt-change-existing-fails-404.md, captures full
# HTTP headers + bodies (including x-ms-request-id), and writes a summary.
#
# Usage:
#   bash bugs/repro-dt-change-fails.sh
#
# Prerequisites:
#   - az cli logged in with access to the registry
#   - The assets listed in the bug doc must exist (model, DTs, environments)
# ==============================================================================
set -uo pipefail

# -- Configuration -------------------------------------------------------------
SUBSCRIPTION_ID="75703df0-38f9-4e2e-8328-45f6fc810286"
RESOURCE_GROUP="mabables-rg"
REGISTRY="mabables-reg-feb26"
REGION="eastus2"

MODEL_NAME="google--gemma-4-31b-it"
MODEL_VERSION="1"

DT_NAME="vllm-google--gemma-4-31b-it"
DT_V1="azureml://registries/${REGISTRY}/deploymentTemplates/${DT_NAME}/versions/1"
DT_V2="azureml://registries/${REGISTRY}/deploymentTemplates/${DT_NAME}/versions/2"
DT_V3="azureml://registries/${REGISTRY}/deploymentTemplates/${DT_NAME}/versions/3"

# MFE Model Registry PATCH URL
MODEL_URL="https://${REGION}.api.azureml.ms/modelregistry/v1.0/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/registries/${REGISTRY}/models/${MODEL_NAME}:${MODEL_VERSION}"

# -- Output directory ----------------------------------------------------------
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
LOG_DIR="$(cd "$(dirname "$0")" && pwd)/repro-logs/${TIMESTAMP}"
mkdir -p "$LOG_DIR"

SUMMARY="$LOG_DIR/summary.md"

# -- Helpers -------------------------------------------------------------------
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_DIR/run.log"; }
hr()  { echo "────────────────────────────────────────────────────────" | tee -a "$LOG_DIR/run.log"; }

get_token() {
  az account get-access-token --query accessToken -o tsv
}

# Get current DT on the model (via CLI)
get_current_dt() {
  local val
  val=$(az ml model show --name "$MODEL_NAME" --version "$MODEL_VERSION" \
    --registry-name "$REGISTRY" \
    --query "default_deployment_template.asset_id" -o tsv 2>/dev/null) || true
  if [[ -z "$val" || "$val" == "None" ]]; then
    echo "(none)"
  else
    echo "$val"
  fi
}

# MFE PATCH with full header/body capture
# Usage: mfe_patch <test_id> <json_payload>
# Writes: <test_id>-request.json, <test_id>-response-headers.txt, <test_id>-response-body.json
mfe_patch() {
  local test_id="$1" payload="$2"
  local token
  token="$(get_token)"

  echo "$payload" > "$LOG_DIR/${test_id}-request.json"

  local http_code
  http_code=$(curl -sS -o "$LOG_DIR/${test_id}-response-body.json" \
    -w "%{http_code}" \
    -D "$LOG_DIR/${test_id}-response-headers.txt" \
    -X PATCH "$MODEL_URL" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$payload")

  echo "$http_code"
}

# CLI model update with full output capture
# Usage: cli_update <test_id> <asset_id>
cli_update() {
  local test_id="$1" asset_id="$2"
  local exit_code=0

  az ml model update --name "$MODEL_NAME" --version "$MODEL_VERSION" \
    --registry-name "$REGISTRY" \
    --resource-group "$RESOURCE_GROUP" \
    --set "default_deployment_template.asset_id=$asset_id" \
    --debug \
    > "$LOG_DIR/${test_id}-response-body.json" \
    2> "$LOG_DIR/${test_id}-debug.log" || exit_code=$?

  echo "$exit_code"
}

# Reset model DT to a known state via remove + add (the workaround)
reset_dt() {
  local target_dt="$1"
  local token
  token="$(get_token)"

  # Remove existing DT (ignore errors if already empty)
  curl -sS -o /dev/null -X PATCH "$MODEL_URL" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d '[{"op":"remove","path":"/defaultDeploymentTemplate"}]' 2>/dev/null || true

  # Brief pause for consistency
  sleep 3

  if [[ "$target_dt" != "(none)" ]]; then
    curl -sS -o /dev/null -X PATCH "$MODEL_URL" \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "[{\"op\":\"add\",\"path\":\"/defaultDeploymentTemplate\",\"value\":{\"assetId\":\"${target_dt}\"}}]" || true
    sleep 3
  fi
}

# Extract correlation/request ID from response headers
get_request_id() {
  local test_id="$1"
  local hdr_file="$LOG_DIR/${test_id}-response-headers.txt"
  local dbg_file="$LOG_DIR/${test_id}-debug.log"
  if [[ -f "$hdr_file" ]]; then
    # Try x-ms-request-id first, then mise-correlation-id, then x-request-id
    local rid
    rid=$(grep -i 'x-ms-request-id' "$hdr_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '\r') || true
    if [[ -z "$rid" ]]; then
      rid=$(grep -i 'mise-correlation-id' "$hdr_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '\r') || true
    fi
    if [[ -z "$rid" ]]; then
      rid=$(grep -i 'x-request-id' "$hdr_file" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '\r') || true
    fi
    echo "${rid:-(no correlation header)}"
  elif [[ -f "$dbg_file" ]]; then
    # For CLI tests, extract the x-ms-request-id from --debug output
    local rid
    rid=$(grep -i 'x-ms-request-id' "$dbg_file" 2>/dev/null | tail -1 | sed "s/.*x-ms-request-id': '//I" | sed "s/'.*//") || true
    if [[ -z "$rid" ]]; then
      rid=$(grep -i 'x-request-id' "$dbg_file" 2>/dev/null | tail -1 | awk '{print $NF}' | tr -d "'" ) || true
    fi
    echo "${rid:-(see debug log)}"
  else
    echo "(n/a)"
  fi
}

# ==============================================================================
# Summary header
# ==============================================================================
cat > "$SUMMARY" <<EOF
# DT Change Bug — Repro Results

**Date**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Registry**: ${REGISTRY} (${REGION})
**Subscription**: ${SUBSCRIPTION_ID}
**Model**: ${MODEL_NAME} v${MODEL_VERSION}
**DT name**: ${DT_NAME}

## Prerequisite checks
EOF

log "Starting DT change bug repro — logs in $LOG_DIR"
hr

# ==============================================================================
# Prerequisite: verify all assets exist
# ==============================================================================
log "Verifying prerequisites..."

prereq_ok=true
for asset_cmd in \
  "az ml deployment-template show --name $DT_NAME --version 1 --registry-name $REGISTRY" \
  "az ml deployment-template show --name $DT_NAME --version 2 --registry-name $REGISTRY" \
  "az ml deployment-template show --name $DT_NAME --version 3 --registry-name $REGISTRY" \
  "az ml environment show --name vllm-server --version 1 --registry-name $REGISTRY" \
  "az ml environment show --name vllm-server --version 2 --registry-name $REGISTRY" \
  "az ml model show --name $MODEL_NAME --version $MODEL_VERSION --registry-name $REGISTRY"; do
  
  short_desc=$(echo "$asset_cmd" | sed 's/--registry-name [^ ]*//' | sed 's/az ml //' | xargs)
  if eval "$asset_cmd" > /dev/null 2>&1; then
    echo "- [x] \`$short_desc\` — exists" >> "$SUMMARY"
    log "  ✓ $short_desc"
  else
    echo "- [ ] \`$short_desc\` — **MISSING**" >> "$SUMMARY"
    log "  ✗ $short_desc — MISSING"
    prereq_ok=false
  fi
done

echo "" >> "$SUMMARY"

if [[ "$prereq_ok" != "true" ]]; then
  echo "**ABORTED**: Missing prerequisites. Cannot run tests." >> "$SUMMARY"
  log "ABORTED: Missing prerequisites."
  cat "$SUMMARY"
  exit 1
fi

# Record CLI version
echo "**CLI version**: $(az version --query '"azure-cli"' -o tsv) / ml ext $(az version --query '"extensions"."ml"' -o tsv 2>/dev/null || echo 'unknown')" >> "$SUMMARY"
echo "" >> "$SUMMARY"

# ==============================================================================
# Test matrix
# ==============================================================================
cat >> "$SUMMARY" <<'EOF'
## Test results

| # | Method | From DT | To DT | Result | HTTP/Exit | Correlation ID | Notes |
|---|--------|---------|-------|--------|-----------|----------------|-------|
EOF

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

record_result() {
  local num="$1" method="$2" from_dt="$3" to_dt="$4" actual="$5" http="$6" req_id="$7" notes="$8"
  TOTAL=$((TOTAL + 1))
  local icon
  if [[ "$actual" == "PASS" ]]; then
    icon="✅ PASS"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    icon="❌ FAIL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  echo "| $num | $method | $from_dt | $to_dt | $icon | $http | \`$req_id\` | $notes |" >> "$SUMMARY"
}

# ==============================================================================
# Test 1: CLI — set same DT (v1 → v1) — should PASS
# ==============================================================================
hr
log "Test 1: CLI set same DT (v1 → v1)"
reset_dt "$DT_V1"
before=$(get_current_dt)
log "  Before: $before"

exit_code=$(cli_update "test1" "$DT_V1")
if [[ "$exit_code" == "0" ]]; then
  result="PASS"
else
  result="FAIL"
fi
log "  Result: $result (exit=$exit_code)"
record_result 1 "CLI \`model update --set\`" "v1" "v1 (same)" "$result" "exit=$exit_code" "$(get_request_id test1)" "Idempotent re-set (baseline)"

# ==============================================================================
# Test 2: CLI — change DT (v1 → v3) — should FAIL (the bug)
# ==============================================================================
hr
log "Test 2: CLI change DT (v1 → v3)"
reset_dt "$DT_V1"
before=$(get_current_dt)
log "  Before: $before"

exit_code=$(cli_update "test2" "$DT_V3")
if [[ "$exit_code" == "0" ]]; then
  result="PASS"
else
  result="FAIL"
fi
log "  Result: $result (exit=$exit_code)"
record_result 2 "CLI \`model update --set\`" "v1" "v3" "$result" "exit=$exit_code" "$(get_request_id test2)" "**BUG** — change existing DT via CLI"

# ==============================================================================
# Test 3: MFE PATCH add — no existing DT → v2 — should PASS
# ==============================================================================
hr
log "Test 3: MFE PATCH add (none → v2)"
reset_dt "(none)"
before=$(get_current_dt)
log "  Before: $before"

http_code=$(mfe_patch "test3" "[{\"op\":\"add\",\"path\":\"/defaultDeploymentTemplate\",\"value\":{\"assetId\":\"${DT_V2}\"}}]")
if [[ "$http_code" =~ ^2 ]]; then
  result="PASS"
else
  result="FAIL"
fi
req_id=$(get_request_id "test3")
log "  Result: $result (HTTP $http_code, request-id=$req_id)"
record_result 3 "MFE PATCH \`add\`" "(none)" "v2" "$result" "$http_code" "$req_id" "Add to empty field (baseline)"

# ==============================================================================
# Test 4: MFE PATCH add — change existing (v2 → v3) — should FAIL (the bug)
# ==============================================================================
hr
log "Test 4: MFE PATCH add (v2 → v3)"
# State: model should have v2 from test 3; verify
before=$(get_current_dt)
log "  Before: $before"

http_code=$(mfe_patch "test4" "[{\"op\":\"add\",\"path\":\"/defaultDeploymentTemplate\",\"value\":{\"assetId\":\"${DT_V3}\"}}]")
if [[ "$http_code" =~ ^2 ]]; then
  result="PASS"
else
  result="FAIL"
fi
req_id=$(get_request_id "test4")
log "  Result: $result (HTTP $http_code, request-id=$req_id)"
record_result 4 "MFE PATCH \`add\`" "v2" "v3" "$result" "$http_code" "$req_id" "**BUG** — change existing DT via PATCH add"

# ==============================================================================
# Test 5: MFE PATCH replace — change existing (v2 → v1) — should FAIL (bug)
# ==============================================================================
hr
log "Test 5: MFE PATCH replace (v2 → v1)"
# State: model should still have v2 (test 4 failed); verify
before=$(get_current_dt)
log "  Before: $before"

http_code=$(mfe_patch "test5" "[{\"op\":\"replace\",\"path\":\"/defaultDeploymentTemplate\",\"value\":{\"assetId\":\"${DT_V1}\"}}]")
if [[ "$http_code" =~ ^2 ]]; then
  result="PASS"
else
  result="FAIL"
fi
req_id=$(get_request_id "test5")
log "  Result: $result (HTTP $http_code, request-id=$req_id)"
record_result 5 "MFE PATCH \`replace\`" "v2" "v1" "$result" "$http_code" "$req_id" "**BUG** — change existing DT via PATCH replace"

# ==============================================================================
# Test 6: MFE PATCH remove — remove DT — should PASS
# ==============================================================================
hr
log "Test 6: MFE PATCH remove (v2 → none)"
before=$(get_current_dt)
log "  Before: $before"

http_code=$(mfe_patch "test6" "[{\"op\":\"remove\",\"path\":\"/defaultDeploymentTemplate\"}]")
if [[ "$http_code" =~ ^2 ]]; then
  result="PASS"
else
  result="FAIL"
fi
req_id=$(get_request_id "test6")
log "  Result: $result (HTTP $http_code, request-id=$req_id)"
record_result 6 "MFE PATCH \`remove\`" "v2" "(none)" "$result" "$http_code" "$req_id" "Remove works (baseline)"

# ==============================================================================
# Test 7: Workaround — remove + add (v1 → v2) — should PASS
# ==============================================================================
hr
log "Test 7: Workaround remove+add (v1 → v2)"
reset_dt "$DT_V1"
before=$(get_current_dt)
log "  Before: $before"

# Step 7a: remove
http_code_a=$(mfe_patch "test7a-remove" "[{\"op\":\"remove\",\"path\":\"/defaultDeploymentTemplate\"}]")
req_id_a=$(get_request_id "test7a-remove")
log "  7a remove: HTTP $http_code_a (request-id=$req_id_a)"
sleep 2

# Step 7b: add
http_code_b=$(mfe_patch "test7b-add" "[{\"op\":\"add\",\"path\":\"/defaultDeploymentTemplate\",\"value\":{\"assetId\":\"${DT_V2}\"}}]")
req_id_b=$(get_request_id "test7b-add")
log "  7b add:    HTTP $http_code_b (request-id=$req_id_b)"

# Verify final state
after=$(get_current_dt)
log "  After: $after"

if [[ "$http_code_a" =~ ^2 && "$http_code_b" =~ ^2 ]]; then
  result="PASS"
else
  result="FAIL"
fi
record_result 7 "Workaround \`remove\`+\`add\`" "v1" "v2" "$result" "${http_code_a}/${http_code_b}" "${req_id_a} / ${req_id_b}" "Two-step workaround succeeds"

# ==============================================================================
# Restore model to DT v1 (clean up)
# ==============================================================================
hr
log "Restoring model to DT v1..."
reset_dt "$DT_V1"
log "  Final state: $(get_current_dt)"

# ==============================================================================
# Summary footer
# ==============================================================================
cat >> "$SUMMARY" <<EOF

## Summary

- **Total tests**: $TOTAL
- **Passed**: $PASS_COUNT
- **Failed**: $FAIL_COUNT (tests 2, 4, 5 — all demonstrate the bug)

**Pattern**: Any operation that *changes* an existing DT to a different version fails.
Operations that set the same value, add to an empty field, remove, or use the two-step
workaround (remove → add) all succeed.

## Failed request details (for service-side correlation)

EOF

for tid in test2 test4 test5; do
  rid=$(get_request_id "$tid")
  hdr_file="$LOG_DIR/${tid}-response-headers.txt"
  body_file="$LOG_DIR/${tid}-response-body.json"
  dbg_file="$LOG_DIR/${tid}-debug.log"

  echo "### $tid" >> "$SUMMARY"
  echo "" >> "$SUMMARY"
  echo "- **Correlation ID**: \`$rid\`" >> "$SUMMARY"

  if [[ -f "$hdr_file" ]]; then
    local_http=$(head -1 "$hdr_file" | awk '{print $2}' | tr -d '\r')
    echo "- **HTTP status**: $local_http" >> "$SUMMARY"
    echo "" >> "$SUMMARY"
    echo "Response headers:" >> "$SUMMARY"
    echo '```' >> "$SUMMARY"
    cat "$hdr_file" >> "$SUMMARY"
    echo '```' >> "$SUMMARY"
  fi

  if [[ -f "$body_file" && -s "$body_file" ]]; then
    echo "" >> "$SUMMARY"
    echo "Response body:" >> "$SUMMARY"
    echo '```json' >> "$SUMMARY"
    python3 -m json.tool "$body_file" 2>/dev/null >> "$SUMMARY" || cat "$body_file" >> "$SUMMARY"
    echo '```' >> "$SUMMARY"
  fi

  if [[ -f "$dbg_file" ]]; then
    echo "" >> "$SUMMARY"
    echo "CLI error (from \`--debug\` log):" >> "$SUMMARY"
    echo '```' >> "$SUMMARY"
    grep -E '^ERROR:|UserError|Invalid containerUri|Could not find' "$dbg_file" 2>/dev/null | head -10 >> "$SUMMARY"
    echo '```' >> "$SUMMARY"
  fi

  echo "" >> "$SUMMARY"
done

cat >> "$SUMMARY" <<EOF

## Log files

All files in: \`$LOG_DIR/\`

| File | Description |
|------|-------------|
| \`run.log\` | Timestamped execution log |
| \`summary.md\` | This summary |
| \`test*-request.json\` | Request payloads sent |
| \`test*-response-body.json\` | Response bodies |
| \`test*-response-headers.txt\` | Full HTTP response headers (includes x-ms-request-id) |
| \`test*-debug.log\` | CLI --debug output (tests 1-2) |

## Environment

\`\`\`
$(az account show -o json 2>&1)
\`\`\`
EOF

hr
log "Done. $PASS_COUNT passed, $FAIL_COUNT failed out of $TOTAL tests."
log "Logs: $LOG_DIR"
log "Summary: $SUMMARY"
hr

cat "$SUMMARY"
