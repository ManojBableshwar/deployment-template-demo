#!/usr/bin/env bash
# ==============================================================================
# run-all.sh -- Execute all steps sequentially with logging
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env.sh"
ensure_log_dir

info "=== Truss PoC: Full Deployment Pipeline ==="
info "Log directory: $LOG_DIR"
info "Started: $(date)"
echo ""

STEPS=(
  "0-validate.sh"
  "1-create-environment.sh"
  "2-register-model.sh"
  "3-create-deployment-template.sh"
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
    err "$step FAILED"
    FAILED=1
    break
  fi
  echo ""
done

echo ""
info "════════════════════════════════════════════"
if [[ $FAILED -eq 0 ]]; then
  ok "All steps completed successfully!"
else
  err "Pipeline stopped due to failure. Check logs: $LOG_DIR/"
fi
info "Finished: $(date)"
info "Logs: $LOG_DIR/"
