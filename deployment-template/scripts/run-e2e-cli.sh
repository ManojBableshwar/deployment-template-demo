#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# run-e2e-cli.sh — End-to-end runner for CLI-based deployment template demo
#
# Usage:
#   ./scripts/run-e2e-cli.sh                     # uses default config
#   ./scripts/run-e2e-cli.sh --config my.sh       # uses custom config
#   E2E_CONFIG=my.sh ./scripts/run-e2e-cli.sh     # alternative config override
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Parse args ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) export E2E_CONFIG="$2"; shift 2 ;;
    *) echo "[ERROR] Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Source environment ───────────────────────────────────────────────────────
source "$SCRIPT_DIR/env.sh"

# ── Check az login ───────────────────────────────────────────────────────────
echo "[PRE-CHECK] Verifying Azure CLI login..."
if ! az account show -o none 2>/dev/null; then
  echo "[ERROR] Not logged in to Azure CLI. Run 'az login' first."
  exit 1
fi
echo "[PRE-CHECK] Logged in as: $(az account show --query user.name -o tsv)"

# ── Create log directory ────────────────────────────────────────────────────
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
PIPELINE_START=$(date +%s)
LOG_DIR="$ROOT_DIR/logs/cli/$TIMESTAMP"
mkdir -p "$LOG_DIR"
echo "[INFO] Logs will be written to: $LOG_DIR"
echo ""

# ── Ordered steps ────────────────────────────────────────────────────────────
STEPS=(
  "1-create-environment.sh"
  "2-create-deployment-template.sh"
  "3-register-model.sh"
  "4-create-online-endpoint.sh"
  "5-create-online-deployment.sh"
  "6-test-inference.sh"
)

PASSED=0
FAILED=0
FAILED_STEPS=()
STEP_TIMINGS=()

for step_file in "${STEPS[@]}"; do
  step_path="$SCRIPT_DIR/cli/$step_file"
  step_name="${step_file%.sh}"
  log_file="$LOG_DIR/${step_name}.log"

  echo "──────────────────────────────────────────────────────────────────"
  echo "[STEP] $step_name"
  echo "──────────────────────────────────────────────────────────────────"

  if [[ ! -f "$step_path" ]]; then
    echo "[ERROR] Script not found: $step_path"
    FAILED=$((FAILED + 1))
    FAILED_STEPS+=("$step_name")
    continue
  fi

  START_TIME=$(date +%s)

  if bash -x "$step_path" 2>&1 | tee "$log_file"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MINS=$((DURATION / 60))
    SECS=$((DURATION % 60))
    echo ""
    echo "[PASS] $step_name completed in ${MINS}m ${SECS}s (${DURATION}s)"
    STEP_TIMINGS+=("$step_name: ${MINS}m ${SECS}s  [PASS]")
    PASSED=$((PASSED + 1))
  else
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MINS=$((DURATION / 60))
    SECS=$((DURATION % 60))
    echo ""
    echo "[FAIL] $step_name failed after ${MINS}m ${SECS}s — see $log_file"
    STEP_TIMINGS+=("$step_name: ${MINS}m ${SECS}s  [FAIL]")
    FAILED=$((FAILED + 1))
    FAILED_STEPS+=("$step_name")
    echo "[ABORT] Stopping pipeline — downstream steps depend on $step_name."
    break
  fi
  echo ""
done

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - PIPELINE_START))
TOTAL_MINS=$((TOTAL_DURATION / 60))
TOTAL_SECS=$((TOTAL_DURATION % 60))

SUMMARY="======================================================================
[SUMMARY] CLI E2E Run — $TIMESTAMP
======================================================================
  Total time: ${TOTAL_MINS}m ${TOTAL_SECS}s
  Passed: $PASSED / ${#STEPS[@]}
  Failed: $FAILED / ${#STEPS[@]}"

if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
  SUMMARY+="
  Failed steps: ${FAILED_STEPS[*]}"
fi

SUMMARY+="
----------------------------------------------------------------------
  Step Timings:"
for timing in "${STEP_TIMINGS[@]}"; do
  SUMMARY+="
    $timing"
done
SUMMARY+="
======================================================================"

echo "$SUMMARY"
echo "$SUMMARY" > "$LOG_DIR/summary.txt"
echo "  Logs:   $LOG_DIR"
echo "======================================================================"

# Write summary to log dir
{
  echo "CLI E2E Run — $TIMESTAMP"
  echo "Passed: $PASSED / ${#STEPS[@]}"
  echo "Failed: $FAILED / ${#STEPS[@]}"
  if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
    echo "Failed steps: ${FAILED_STEPS[*]}"
  fi
} > "$LOG_DIR/summary.txt"

[[ $FAILED -eq 0 ]]
