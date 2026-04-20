#!/usr/bin/env bash
# generate-model-readme.sh — Generate/update a model-specific README.md
#
# Parses E2E logs, summary, inference results, and benchmark data to produce
# a human-readable status page. Appends a changelog entry for each run.
#
# Usage:
#   source env.sh  (sets MODEL_ROOT, HF_MODEL_ID, etc.)
#   bash generate-model-readme.sh [LOG_DIR]
#
# If LOG_DIR is not provided, uses the latest directory under $LOG_BASE/e2e/.
# Output: $MODEL_ROOT/README.md
#
# SECURITY: All API keys, tokens, auth headers, and credentials are scrubbed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source env if not already loaded
if [[ -z "${MODEL_ROOT:-}" ]]; then
  source "$SCRIPT_DIR/env.sh"
fi

README="$MODEL_ROOT/README.md"
LOG_BASE_DIR="$MODEL_ROOT/logs/e2e"

# Determine which log dir to use
if [[ -n "${1:-}" ]]; then
  RUN_LOG_DIR="$1"
else
  # Latest run by directory name (timestamp-sorted)
  RUN_LOG_DIR=$(ls -1d "$LOG_BASE_DIR"/*/ 2>/dev/null | sort | tail -1)
  RUN_LOG_DIR="${RUN_LOG_DIR%/}"
fi

if [[ -z "$RUN_LOG_DIR" || ! -d "$RUN_LOG_DIR" ]]; then
  echo "[WARN] No log directory found — skipping README generation."
  exit 0
fi

RUN_TIMESTAMP=$(basename "$RUN_LOG_DIR")

# ── Scrubbing function ──────────────────────────────────────────────────────
# Strips API keys, tokens, auth headers, SAS URIs, and other sensitive values
scrub() {
  sed -E \
    -e 's/(Authorization: Bearer )[^ "]+/\1***REDACTED***/gi' \
    -e 's/(api-key: )[^ "]+/\1***REDACTED***/gi' \
    -e 's/(Bearer )[a-zA-Z0-9_.~+/=-]{20,}/\1***REDACTED***/g' \
    -e 's/(primaryKey|secondaryKey)["'"'"']*[=: ]+["'"'"']*[a-zA-Z0-9_.~+/=-]{10,}/\1=***REDACTED***/gi' \
    -e 's/(API_KEY=)[^ ]+/\1***REDACTED***/g' \
    -e 's/(HF_TOKEN=)[^ ]+/\1***REDACTED***/g' \
    -e 's/(hf_)[a-zA-Z0-9]{10,}/\1***REDACTED***/g' \
    -e 's/(\?|&)(sig|se|st|sv|sp|sr|sks|skt|ske|skoid|sktid|skv)=[^& "]+/\1\2=***REDACTED***/g' \
    -e 's|https://[a-z0-9]+\.blob\.core\.windows\.net/[^ ]*\?[^ ]*|https://***.blob.core.windows.net/***?***REDACTED***|g' \
    -e 's/(eyJ)[a-zA-Z0-9_.-]{50,}/***JWT_REDACTED***/g'
}

# ── Parse summary.txt ────────────────────────────────────────────────────────
SUMMARY_FILE="$RUN_LOG_DIR/summary.txt"
RUN_STATUS="unknown"
RUN_PASSED=0
RUN_FAILED=0
RUN_TOTAL=0
RUN_TIME=""
RUN_SKUS=""
RUN_VERSIONS=""
RUN_COMMAND=""
FAILED_STEPS=""

if [[ -f "$SUMMARY_FILE" ]]; then
  RUN_SKUS=$(grep 'SKUs:' "$SUMMARY_FILE" 2>/dev/null | head -1 | sed 's/.*SKUs:[[:space:]]*//' || true)
  RUN_VERSIONS=$(grep 'Versions:' "$SUMMARY_FILE" 2>/dev/null | head -1 | sed 's/.*Versions:[[:space:]]*//' || true)
  RUN_TIME=$(grep 'Total time:' "$SUMMARY_FILE" 2>/dev/null | head -1 | sed 's/.*Total time:[[:space:]]*//' || true)
  RUN_COMMAND=$(grep 'Command:' "$SUMMARY_FILE" 2>/dev/null | head -1 | sed 's/.*Command:[[:space:]]*//' | scrub || true)
  RUN_PASSED=$(grep 'Passed:' "$SUMMARY_FILE" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1 || true)
  RUN_FAILED=$(grep 'Failed:' "$SUMMARY_FILE" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1 || true)
  RUN_TOTAL=$(grep 'Passed:' "$SUMMARY_FILE" 2>/dev/null | head -1 | grep -oE '[0-9]+' | tail -1 || true)
  FAILED_STEPS=$(grep 'Failed steps:' "$SUMMARY_FILE" 2>/dev/null | head -1 | sed 's/.*Failed steps:[[:space:]]*//' || true)
  if [[ "$RUN_FAILED" == "0" ]]; then
    RUN_STATUS="PASSED"
  else
    RUN_STATUS="FAILED"
  fi
else
  # No summary.txt — infer status from log files
  # Count steps by looking at which main step logs exist
  _total_logs=$(ls "$RUN_LOG_DIR"/[0-7]-*.log 2>/dev/null | grep -v 'endpoint-\|deploy-\|inference-\|bench-' | wc -l | tr -d ' ' || echo 0)
  # Check if any step scripts are still running
  if pgrep -f "run-e2e-cli.*${HF_MODEL_ID}" >/dev/null 2>&1; then
    RUN_STATUS="IN PROGRESS"
  else
    # Finished but no summary — likely killed or crashed
    RUN_STATUS="INCOMPLETE (no summary)"
  fi
  RUN_PASSED="?"
  RUN_FAILED="?"
  RUN_TOTAL="$_total_logs steps logged"
  RUN_TIME="(no summary.txt)"
  # Try to extract versions from the main E2E log (step 2)
  _dt_log="$RUN_LOG_DIR/2-create-deployment-template.log"
  if [[ -f "$_dt_log" ]]; then
    RUN_VERSIONS=$(grep -oE 'model=[0-9]+  env=[0-9]+  dt=[0-9]+' "$_dt_log" 2>/dev/null | head -1 || true)
  fi
  # Try to extract SKUs from sub-logs
  _skus=""
  [[ -f "$RUN_LOG_DIR/4-endpoint-h100.log" || -f "$RUN_LOG_DIR/5-deploy-h100.log" ]] && _skus="h100"
  [[ -f "$RUN_LOG_DIR/4-endpoint-a100.log" || -f "$RUN_LOG_DIR/5-deploy-a100.log" ]] && _skus="${_skus:+$_skus }a100"
  RUN_SKUS="${_skus:-unknown}"
  # Build a step table from log file existence
  STEP_TABLE="  (No summary.txt — reconstructed from log files)"
  for _step_log in "$RUN_LOG_DIR"/[0-7]-*.log; do
    [[ -f "$_step_log" ]] || continue
    _sname=$(basename "$_step_log" .log)
    # Skip sub-logs (endpoint-a100, deploy-h100, etc.)
    case "$_sname" in
      *-a100|*-h100|*-endpoint-*|*-deploy-*|*-inference-*|*-bench-*) continue ;;
    esac
    STEP_TABLE+=$'\n'"  $_sname"
  done
fi

# ── Parse step table from summary (only if we didn't already build one) ───────
if [[ -f "$SUMMARY_FILE" ]]; then
  STEP_TABLE=$(awk '/^  STEP /,/^====/' "$SUMMARY_FILE" | grep -vE '^====|^  ----|^$' | head -20 || true)
fi

# ── Inference results ────────────────────────────────────────────────────────
# Support both old (curl-based) and new (llm-api-spec) formats
INFERENCE_SECTION=""

for sku in h100 a100; do
  _SKU=$(echo "$sku" | tr '[:lower:]' '[:upper:]')
  md_report="$RUN_LOG_DIR/6-inference-${sku}.md"
  json_report="$RUN_LOG_DIR/6-inference-${sku}.json"
  log_file="$RUN_LOG_DIR/6-inference-${sku}.log"

  if [[ -f "$json_report" ]]; then
    # New llm-api-spec format
    _summary=$(python3 -c "
import json
with open('$json_report') as f:
    data = json.load(f)
s = data.get('summary', {})
print(f\"Passed: {s.get('passed',0)} | Failed: {s.get('failed',0)} | Unsupported: {s.get('unsupported',0)} | N/A: {s.get('not_applicable',0)} | Total: {s.get('total',0)}\")
" 2>/dev/null || echo "Error reading JSON report")

    INFERENCE_SECTION+="
#### $_SKU — llm-api-spec results

$_summary
"
    # Extract the results table from the markdown report if available
    if [[ -f "$md_report" ]]; then
      _table=$(awk '/^\| #/,/^$/' "$md_report" | head -30)
      if [[ -n "$_table" ]]; then
        INFERENCE_SECTION+="
$_table
"
      fi
    fi

  elif [[ -f "$log_file" ]]; then
    # Old curl-based format — extract the JSON response
    _response=$(grep -A50 '"choices"' "$log_file" 2>/dev/null | head -20 | scrub || true)
    if [[ -n "$_response" ]]; then
      _status="Received response"
      # Check for errors
      if grep -q '"error"' "$log_file" 2>/dev/null; then
        _status="ERROR"
      fi
      INFERENCE_SECTION+="
#### $_SKU — $_status

<details>
<summary>Response snippet</summary>

\`\`\`json
$(echo "$_response" | head -15)
\`\`\`

</details>
"
    fi
  fi
done

# ── Benchmark summary ────────────────────────────────────────────────────────
BENCH_DIR="$RUN_LOG_DIR/benchmark"
BENCHMARK_SECTION=""

if [[ -d "$BENCH_DIR" ]]; then
  for sku_dir in "$BENCH_DIR"/h100 "$BENCH_DIR"/a100; do
    [[ -d "$sku_dir" ]] || continue
    sku_label=$(basename "$sku_dir")
    _SKU_LABEL=$(echo "$sku_label" | tr '[:lower:]' '[:upper:]')
    run_count=$(find "$sku_dir" -name "profile_export_aiperf.json" 2>/dev/null | wc -l | tr -d ' ')
    error_count=0
    if [[ $run_count -gt 0 ]]; then
      # Extract key metrics from the first short-gen run
      _sample=$(find "$sku_dir" -path "*/c2_in*_out*/profile_export_aiperf.json" 2>/dev/null | head -1)
      _metrics=""
      if [[ -n "$_sample" && -f "$_sample" ]]; then
        _metrics=$(python3 -c "
import json
try:
    with open('$_sample') as f:
        d = json.load(f)
    ttft = d.get('time_to_first_token',{}).get('avg')
    itl = d.get('inter_token_latency',{}).get('avg')
    otps = d.get('output_token_throughput_per_request',{}).get('avg')
    parts = []
    if ttft is not None: parts.append(f'TTFT(avg): {float(ttft):.1f}ms')
    if itl is not None: parts.append(f'ITL(avg): {float(itl):.1f}ms')
    if otps is not None: parts.append(f'OT/s(avg): {float(otps):.1f} tok/s')
    print(' | '.join(parts) if parts else 'no metrics')
except Exception as e:
    print(f'error: {e}')
" 2>/dev/null || echo "metrics unavailable")
      fi
      # Count total errors across all runs
      error_count=$(python3 -c "
import json, glob
total = 0
for f in glob.glob('$sku_dir/*/profile_export_aiperf.json'):
    with open(f) as fh:
        d = json.load(fh)
        total += int(d.get('error_count',{}).get('avg',0))
print(total)
" 2>/dev/null || echo "0")

      BENCHMARK_SECTION+="
#### $_SKU_LABEL

- **Benchmark runs:** $run_count
- **Total errors:** $error_count
- **Sample metrics (c=2):** $_metrics
"
    fi
  done
fi

# ── Plots ─────────────────────────────────────────────────────────────────────
PLOTS_SECTION=""
PLOTS_DIR="$BENCH_DIR/plots"
if [[ -d "$PLOTS_DIR" ]]; then
  # Use relative paths from the README location ($MODEL_ROOT)
  _rel_plots="logs/e2e/$RUN_TIMESTAMP/benchmark/plots"
  PLOTS_SECTION="### Benchmark Plots

"
  for plot in benchmark_avg.png benchmark_p50.png benchmark_p90.png errors.png; do
    if [[ -f "$PLOTS_DIR/$plot" ]]; then
      _label=$(echo "$plot" | sed 's/.png//' | sed 's/_/ /g' | python3 -c "import sys; print(sys.stdin.read().strip().title())")
      PLOTS_SECTION+="#### $_label

![$_label]($_rel_plots/$plot)

"
    fi
  done

  # Percentile shape plots (collapsible)
  _perc_plots=$(ls "$PLOTS_DIR"/percentiles_*.png 2>/dev/null || true)
  if [[ -n "$_perc_plots" ]]; then
    PLOTS_SECTION+="<details>
<summary>Percentile breakdown by token shape</summary>

"
    for plot in "$PLOTS_DIR"/percentiles_*.png; do
      [[ -f "$plot" ]] || continue
      _fname=$(basename "$plot")
      _label=$(echo "$_fname" | sed 's/.png//' | sed 's/_/ /g' | python3 -c "import sys; print(sys.stdin.read().strip().title())")
      PLOTS_SECTION+="#### $_label

![$_label]($_rel_plots/$_fname)

"
    done
    PLOTS_SECTION+="</details>
"
  fi
fi

# ── Build the changelog entry ────────────────────────────────────────────────
CHANGELOG_ENTRY="| $RUN_TIMESTAMP | $RUN_STATUS | $RUN_VERSIONS | $RUN_SKUS | $RUN_TIME | ${RUN_PASSED:-0}/${RUN_TOTAL:-?} passed | ${FAILED_STEPS:---} |"

# ── Preserve existing changelog ──────────────────────────────────────────────
EXISTING_CHANGELOG=""
if [[ -f "$README" ]]; then
  # Extract everything after "## Changelog" (skip the header row and separator)
  EXISTING_CHANGELOG=$(awk '/^## Changelog/,0' "$README" | tail -n+2 | grep '^|' | grep -v '^| Run ' | grep -v '^|---' || true)
  # Deduplicate: remove the entry for this timestamp if it already exists
  EXISTING_CHANGELOG=$(echo "$EXISTING_CHANGELOG" | grep -v "^| $RUN_TIMESTAMP " || true)
fi

# ── Write README ─────────────────────────────────────────────────────────────
cat > "$README" << READMEEOF
# ${HF_MODEL_ID}

> Auto-generated status page — updated by E2E pipeline runs.
> Last updated: $(date '+%Y-%m-%d %H:%M:%S')

## Latest Run

| Field | Value |
|-------|-------|
| **Timestamp** | \`$RUN_TIMESTAMP\` |
| **Status** | **$RUN_STATUS** |
| **Versions** | $RUN_VERSIONS |
| **SKUs** | $RUN_SKUS |
| **Total time** | $RUN_TIME |
| **Steps** | ${RUN_PASSED:-0}/${RUN_TOTAL:-?} passed |
| **Failed** | ${FAILED_STEPS:---} |

### Command

\`\`\`bash
$RUN_COMMAND
\`\`\`

### Step Results

\`\`\`
$(echo "$STEP_TABLE" | scrub)
\`\`\`

## Inference API Tests
$INFERENCE_SECTION
READMEEOF

# Append benchmark section if it exists
if [[ -n "$BENCHMARK_SECTION" ]]; then
  cat >> "$README" << BENCHEOF

## Benchmark Summary
$BENCHMARK_SECTION
BENCHEOF
fi

# Append plots section if it exists
if [[ -n "$PLOTS_SECTION" ]]; then
  cat >> "$README" << PLOTEOF

$PLOTS_SECTION
PLOTEOF
fi

# Append changelog
cat >> "$README" << LOGEOF

## Changelog

| Run | Status | Versions | SKUs | Duration | Steps | Failed |
|-----|--------|----------|------|----------|-------|--------|
$CHANGELOG_ENTRY
$EXISTING_CHANGELOG
LOGEOF

echo "[INFO] README updated: $README"
