#!/usr/bin/env bash
# Step 4: Create managed online endpoints (SKU-aware, parallel)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"

read -ra SKUS <<< "${E2E_SKUS:-a100 h100}"
_step_start "Step 4: Create online endpoints (${SKUS[*]})"

sku_endpoint_yaml() {
  case "$1" in
    a100) echo "$YAML_DIR/endpoint-a100.yml" ;;
    h100) echo "$YAML_DIR/endpoint-h100.yml" ;;
  esac
}

sku_endpoint_name() {
  local ep_yaml
  ep_yaml=$(sku_endpoint_yaml "$1")
  python3 -c "
import yaml, sys
with open('$ep_yaml') as f:
    print(yaml.safe_load(f)['name'])
" 2>/dev/null || grep '^name:' "$ep_yaml" | awk '{print $2}'
}

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

info "Creating endpoints in parallel for: ${SKUS[*]}"

PIDS=()
for sku in "${SKUS[@]}"; do
  yaml_file=$(sku_endpoint_yaml "$sku")
  ep_name=$(sku_endpoint_name "$sku")
  log_file="${E2E_LOG_DIR:-/tmp}/4-endpoint-${sku}.log"

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

for sku in "${SKUS[@]}"; do
  yaml_file=$(sku_endpoint_yaml "$sku")
  ep_name=$(sku_endpoint_name "$sku")
  info "$sku endpoint:"
  az ml online-endpoint show --name "$ep_name" --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" -o json
done

_step_end
