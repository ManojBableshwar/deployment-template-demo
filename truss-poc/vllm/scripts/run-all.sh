#!/usr/bin/env bash
# ==============================================================================
# run-all.sh -- Full Truss+vLLM deployment pipeline (mounted weights)
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Truss + vLLM PoC: Full Pipeline ==="
info "Log directory: $LOG_DIR"
echo ""

STEPS=(
  "0-validate.sh"
  "1-create-environment.sh"
  "2b-register-model-manifest.sh"   # mounted weights + AOT manifest (no baking)
  "3-create-deployment-template.sh"
  "3b-tag-model-dt.sh"
  "4-create-endpoint.sh"
  "5-create-deployment.sh"
  "6-route-traffic.sh"
  "7-test-inference.sh"
  "8-verify-health.sh"
)

FAILED=0
for step in "${STEPS[@]}"; do
  info "────────────────────────────────────────────"
  info "Running: $step"
  info "────────────────────────────────────────────"
  if bash "$SCRIPT_DIR/$step"; then
    ok "$step completed"
  else
    err "$step FAILED"; FAILED=1; break
  fi
  echo ""
done

echo ""
if [[ $FAILED -eq 0 ]]; then
  ok "All steps completed successfully!"
else
  err "Pipeline stopped due to failure. Check logs: $LOG_DIR/"
fi
info "Logs: $LOG_DIR/"
