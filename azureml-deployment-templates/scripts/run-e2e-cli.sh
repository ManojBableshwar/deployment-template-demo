#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# run-e2e-cli.sh -- End-to-end runner for CLI-based deployment template demo
#
# Usage:
#   ./scripts/run-e2e-cli.sh --hf-model Qwen/Qwen3.5-0.8B
#   ./scripts/run-e2e-cli.sh --hf-model Qwen/Qwen3.5-0.8B --sku Standard_NC40ads_H100_v5
#   ./scripts/run-e2e-cli.sh --hf-model Qwen/Qwen3.5-0.8B --version 51
#   ./scripts/run-e2e-cli.sh --hf-model Qwen/Qwen3.5-0.8B --version 51 --env-version 60
# ------------------------------------------------------------------------------
set -euo pipefail

# Capture the original command for logging
E2E_CLI_CMD="$0 $*"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -- Parse args ---------------------------------------------------------------
E2E_SKUS_ARG=()
E2E_TPS_ARG=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hf-model) export HF_MODEL_ID="$2"; shift 2 ;;
    --version) export ASSET_VERSION="$2"; shift 2 ;;
    --model-version) export MODEL_VERSION="$2"; shift 2 ;;
    --env-name) export ENVIRONMENT_NAME="$2"; shift 2 ;;
    --env-version) export ENVIRONMENT_VERSION="$2"; shift 2 ;;
    --dt-version) export TEMPLATE_VERSION="$2"; shift 2 ;;
    --tp) E2E_TPS_ARG+=("$2"); shift 2 ;;
    --sku)
      case "$2" in
        Standard_NC24ads_A100_v4)  E2E_SKUS_ARG+=("a100"); export INSTANCE_TYPE_A100="$2" ;;
        Standard_NC48ads_A100_v4)  E2E_SKUS_ARG+=("a100"); export INSTANCE_TYPE_A100="$2" ;;
        Standard_NC40ads_H100_v5)  E2E_SKUS_ARG+=("h100"); export INSTANCE_TYPE_H100="$2" ;;
        Standard_NC80adis_H100_v5) E2E_SKUS_ARG+=("h100"); export INSTANCE_TYPE_H100="$2" ;;
        *) echo "[ERROR] Unknown SKU: $2"; echo "  Supported: Standard_NC24ads_A100_v4, Standard_NC48ads_A100_v4, Standard_NC40ads_H100_v5, Standard_NC80adis_H100_v5"; exit 1 ;;
      esac
      shift 2 ;;
    *) echo "[ERROR] Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "${HF_MODEL_ID:-}" ]]; then
  echo "[ERROR] --hf-model is required."
  echo "  Usage: run-e2e-cli.sh --hf-model Qwen/Qwen3.5-0.8B [--tp 1 --tp 2] [--sku ...]"
  exit 1
fi

# Default to both SKUs if none specified
if [[ ${#E2E_SKUS_ARG[@]} -eq 0 ]]; then
  E2E_SKUS_ARG=("a100" "h100")
fi
export E2E_SKUS="${E2E_SKUS_ARG[*]}"

# Default to TP=1 if none specified
if [[ ${#E2E_TPS_ARG[@]} -eq 0 ]]; then
  E2E_TPS_ARG=("1")
fi
export E2E_TPS="${E2E_TPS_ARG[*]}"

echo "[INFO] Command: $E2E_CLI_CMD"
echo "[INFO] HF Model: $HF_MODEL_ID"
echo "[INFO] Target TPs: $E2E_TPS"
echo "[INFO] Target SKUs: $E2E_SKUS"

# -- Source environment (resolves HF_MODEL_ID → paths & names) ----------------
source "$SCRIPT_DIR/env.sh"

echo "[INFO] Model slug: $MODEL_SLUG"
echo "[INFO] Model dir: $MODEL_ROOT"
echo "[INFO] Versions: model=$MODEL_VERSION  env=$ENVIRONMENT_VERSION  dt=$TEMPLATE_VERSION"

# -- Bootstrap model directory from templates if needed -----------------------
if [[ ! -d "$MODEL_ROOT" ]]; then
  echo "[INFO] Creating model directory: $MODEL_ROOT"
  mkdir -p "$MODEL_ROOT/model-artifacts" "$MODEL_ROOT/yaml/docker" "$MODEL_ROOT/logs"
fi

# -- Hydrate YAML templates ---------------------------------------------------
echo "[INFO] Hydrating YAML templates..."
hydrate_yaml

# -- Check az login -----------------------------------------------------------
echo "[PRE-CHECK] Verifying Azure CLI login..."
if ! az account show -o none 2>/dev/null; then
  echo "[ERROR] Not logged in to Azure CLI. Run 'az login' first."
  exit 1
fi
echo "[PRE-CHECK] Logged in as: $(az account show --query user.name -o tsv)"

# -- Create log directory -----------------------------------------------------
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
PIPELINE_START=$(date +%s)
LOG_DIR="$LOG_BASE/e2e/$TIMESTAMP"
mkdir -p "$LOG_DIR"
export E2E_LOG_DIR="$LOG_DIR"
echo "[INFO] Logs will be written to: $LOG_DIR"
echo ""

# -- Ordered steps ------------------------------------------------------------
STEPS=(
  "0-validate-model.sh"
  "1-create-environment.sh"
  "2-create-deployment-template.sh"
  "3-register-model.sh"
  "4-create-online-endpoint.sh"
  "5-create-online-deployment.sh"
  "6-test-inference.sh"
  "7-benchmark.sh"
)

PASSED=0
FAILED=0
FAILED_STEPS=()
STEP_TIMINGS=()

# Map step number to sub-log glob pattern (parallel sub-tasks)
# Sub-logs: 4-endpoint-{sku}.log, 5-deploy-{sku}.log,
#           6-inference-{sku}.log, benchmark/7-bench-{sku}.log
_sub_log_pattern() {
  local step_num="${1%%-*}"  # e.g. "4" from "4-create-online-endpoint"
  case "$step_num" in
    4) echo "$LOG_DIR/4-endpoint-*.log" ;;
    5) echo "$LOG_DIR/5-deploy-*.log" ;;
    6) echo "$LOG_DIR/6-inference-*.log" ;;
    7) echo "$LOG_DIR/benchmark/7-bench-*.log" ;;
    *) echo "" ;;
  esac
}

# Extract TP×SKU label from a sub-log filename (e.g. "5-deploy-tp1-h100.log" → "tp1-h100")
_sub_log_label() {
  local fname
  fname="$(basename "$1" .log)"
  # Strip the step prefix (e.g. "5-deploy-" or "7-bench-") to get "tp1-h100"
  echo "${fname#*-*-}"
}

# Detect action for a sub-log: SKIPPED vs CREATED
_sub_log_action() {
  if grep -qi '-- skipping' "$1" 2>/dev/null; then
    echo "SKIPPED (already exists)"
  else
    echo "CREATED"
  fi
}

# Compute elapsed time from sub-log file timestamps (birth → mtime)
_sub_log_time() {
  local birth mtime dur m s
  birth=$(stat -f %B "$1" 2>/dev/null) || return
  mtime=$(stat -f %m "$1" 2>/dev/null) || return
  dur=$((mtime - birth))
  [[ $dur -ge 0 ]] || dur=0
  m=$((dur / 60))
  s=$((dur % 60))
  printf '%dm %02ds' "$m" "$s"
}

# Collect sub-task lines for a step and append to STEP_TIMINGS
_collect_sub_tasks() {
  local step_name="$1"
  local sub_pattern
  sub_pattern=$(_sub_log_pattern "$step_name")
  [[ -n "$sub_pattern" ]] || return 0
  for sub_log in $sub_pattern; do
    [[ -f "$sub_log" ]] || continue
    local sub_label sub_action sub_time
    sub_label=$(_sub_log_label "$sub_log")
    sub_action=$(_sub_log_action "$sub_log")
    sub_time=$(_sub_log_time "$sub_log")
    STEP_TIMINGS+=("$(printf '  └─ %-32s %10s  %-8s  %s' "$sub_label" "$sub_time" "" "$sub_action")")
  done
}

for step_file in "${STEPS[@]}"; do
  step_path="$SCRIPT_DIR/cli/$step_file"
  step_name="${step_file%.sh}"
  log_file="$LOG_DIR/${step_name}.log"

  echo "------------------------------------------------------------------"
  echo "[STEP] $step_name"
  echo "------------------------------------------------------------------"

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
    # Detect whether the step actually created something or skipped
    if grep -qi '-- skipping' "$log_file" 2>/dev/null; then
      ACTION="SKIPPED (asset already exists)"
    else
      ACTION="CREATED"
    fi
    echo ""
    echo "[PASS] $step_name completed in ${MINS}m ${SECS}s (${DURATION}s)"
    STEP_TIMINGS+=("$(printf '%-36s %6dm %02ds  %-8s  %s' "$step_name" "$MINS" "$SECS" "[PASS]" "$ACTION")")

    # Collect parallel sub-task logs (e.g. per-SKU deploy/endpoint/inference/benchmark)
    _collect_sub_tasks "$step_name"

    PASSED=$((PASSED + 1))
  else
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MINS=$((DURATION / 60))
    SECS=$((DURATION % 60))
    echo ""
    echo "[FAIL] $step_name failed after ${MINS}m ${SECS}s -- see $log_file"
    STEP_TIMINGS+=("$(printf '%-36s %6dm %02ds  %-8s' "$step_name" "$MINS" "$SECS" "[FAIL]")")

    # Still collect sub-logs on failure to show which SKU failed
    _collect_sub_tasks "$step_name"

    FAILED=$((FAILED + 1))
    FAILED_STEPS+=("$step_name")
    echo "[ABORT] Stopping pipeline -- downstream steps depend on $step_name."
    break
  fi
  echo ""
done

# -- Summary ------------------------------------------------------------------
TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - PIPELINE_START))
TOTAL_MINS=$((TOTAL_DURATION / 60))
TOTAL_SECS=$((TOTAL_DURATION % 60))

SUMMARY="======================================================================
[SUMMARY] CLI E2E Run -- $TIMESTAMP -- model=$HF_MODEL_ID
======================================================================
  Command:    $E2E_CLI_CMD
  TPs:        $E2E_TPS
  SKUs:       $E2E_SKUS
  Versions:   model=$MODEL_VERSION  env=$ENVIRONMENT_VERSION  dt=$TEMPLATE_VERSION
  Total time: ${TOTAL_MINS}m ${TOTAL_SECS}s
  Passed: $PASSED / ${#STEPS[@]}
  Failed: $FAILED / ${#STEPS[@]}"

if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
  SUMMARY+="
  Failed steps: ${FAILED_STEPS[*]}"
fi

SUMMARY+="
----------------------------------------------------------------------
$(printf '  %-36s %9s  %-8s  %s\n' "STEP" "TIME" "STATUS" "ACTION")
$(printf '  %-36s %9s  %-8s  %s\n' "----" "----" "------" "------")"
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

# -- Generate benchmark plots (non-fatal, works for partial runs) -------------
BENCH_DIR="$LOG_DIR/benchmark"
PLOT_SCRIPT="$SCRIPT_DIR/plot-benchmark.py"
if [[ -d "$BENCH_DIR" && -f "$PLOT_SCRIPT" ]]; then
  # Prefer .venv python (has matplotlib) over system python
  _plot_py=python3
  _venv_py="$(cd "$SCRIPT_DIR/../.." && pwd)/.venv/bin/python3"
  if [[ -x "$_venv_py" ]]; then
    _plot_py="$_venv_py"
  fi
  echo "[INFO] Generating benchmark plots (including partial runs)..."
  if "$_plot_py" "$PLOT_SCRIPT" "$BENCH_DIR" 2>/dev/null; then
    echo "  Plots:  $BENCH_DIR/plots/"
  else
    echo "[WARN] Plot generation failed (non-fatal)"
  fi

  # Interactive HTML dashboard (no extra deps, uses stdlib only)
  DASH_SCRIPT="$SCRIPT_DIR/benchmark-dashboard.py"
  if [[ -f "$DASH_SCRIPT" ]]; then
    echo "[INFO] Generating interactive benchmark dashboard..."
    if python3 "$DASH_SCRIPT" "$BENCH_DIR" -o "$BENCH_DIR/plots/benchmark-dashboard.html" 2>/dev/null; then
      echo "  Dashboard: $BENCH_DIR/plots/benchmark-dashboard.html"
    else
      echo "[WARN] Dashboard generation failed (non-fatal)"
    fi
  fi
fi

# -- Generate/update model README (non-fatal) --------------------------------
if bash "$SCRIPT_DIR/generate-model-readme.sh" "$LOG_DIR" 2>/dev/null; then
  echo "  README: $MODEL_ROOT/README.md"
else
  echo "[WARN] README generation failed (non-fatal)"
fi

[[ $FAILED -eq 0 ]]
