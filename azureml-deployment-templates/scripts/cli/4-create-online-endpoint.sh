#!/usr/bin/env bash
# Step 4: Create managed online endpoints (TP×SKU-aware, parallel)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"

read -ra TPS <<< "${E2E_TPS:-1}"
read -ra SKUS <<< "${E2E_SKUS:-a100 h100}"
_step_start "Step 4: Create online endpoints (TP=${TPS[*]} × SKU=${SKUS[*]})"

create_endpoint() {
  local ep_name="$1" yaml_file="$2"
  if az ml online-endpoint show --name "$ep_name" --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    info "[$ep_name] Already exists -- skipping."
  else
    info "[$ep_name] Creating..."
    az ml online-endpoint create \
      --file "$yaml_file" \
      --workspace-name "$AZUREML_WORKSPACE" \
      --resource-group "$RESOURCE_GROUP"
    info "[$ep_name] Created."
  fi
}

# Build list of all TP×SKU combos
COMBOS=()
for tp in "${TPS[@]}"; do
  for sku in "${SKUS[@]}"; do
    COMBOS+=("${tp}:${sku}")
  done
done

info "Creating endpoints in parallel for: ${COMBOS[*]}"

PIDS=()
for combo in "${COMBOS[@]}"; do
  tp="${combo%%:*}"
  sku="${combo##*:}"
  ep_name=$(tp_sku_endpoint_name "$tp" "$sku")
  yaml_file="$YAML_DIR/endpoint-tp${tp}-${sku}.yml"
  log_file="${E2E_LOG_DIR:-/tmp}/4-endpoint-tp${tp}-${sku}.log"

  create_endpoint "$ep_name" "$yaml_file" \
    > >(tee "$log_file") 2>&1 &
  PIDS+=($!)
done

EP_FAILED=0
for pid in "${PIDS[@]}"; do
  if ! wait "$pid"; then EP_FAILED=1; fi
done
if [[ "$EP_FAILED" -ne 0 ]]; then
  err "One or more endpoint creations failed."
  exit 1
fi

for combo in "${COMBOS[@]}"; do
  tp="${combo%%:*}"
  sku="${combo##*:}"
  ep_name=$(tp_sku_endpoint_name "$tp" "$sku")
  info "tp${tp}-${sku} endpoint:"
  az ml online-endpoint show --name "$ep_name" --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" -o json
done

_step_end
