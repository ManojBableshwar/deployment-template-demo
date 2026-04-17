#!/usr/bin/env bash
# Step 5: Create online deployments (SKU-aware, parallel)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"

read -ra SKUS <<< "${E2E_SKUS:-a100 h100}"
_step_start "Step 5: Create online deployments (${SKUS[*]})"

DESIRED_MODEL="azureml://registries/${AZUREML_REGISTRY}/models/${MODEL_NAME}/versions/${MODEL_VERSION}"

sku_endpoint_name() {
  case "$1" in
    a100) echo "qwen35-ep-a100" ;;
    h100) echo "qwen35-ep-h100" ;;
  esac
}

sku_deployment_yaml() {
  case "$1" in
    a100) echo "$SCRIPT_DIR/yaml/deployment-a100.yml" ;;
    h100) echo "$SCRIPT_DIR/yaml/deployment-h100.yml" ;;
  esac
}

deploy_one() {
  local sku="$1"
  local ep_name dep_name yaml_file
  ep_name=$(sku_endpoint_name "$sku")
  dep_name="qwen35-vllm"
  yaml_file=$(sku_deployment_yaml "$sku")

  if existing_json=$(az ml online-deployment show \
        --name "$dep_name" --endpoint-name "$ep_name" \
        --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" \
        -o json 2>/dev/null); then
    existing_model=$(printf '%s' "$existing_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('model',''))")
    provisioning_state=$(printf '%s' "$existing_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('provisioning_state',''))")

    if [[ "$existing_model" == "$DESIRED_MODEL" && "$provisioning_state" == "Succeeded" ]]; then
      info "[$sku] Already exists with desired model -- skipping."
      return 0
    fi
    info "[$sku] Stale or failed (state=$provisioning_state). Recreating..."
    az ml online-deployment delete \
      --name "$dep_name" --endpoint-name "$ep_name" \
      --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" \
      --yes
  fi

  info "[$sku] Creating deployment..."
  az ml online-deployment create \
    --file "$yaml_file" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --all-traffic
  info "[$sku] Created."
}

info "Deploying in parallel for: ${SKUS[*]}"

PIDS=()
for sku in "${SKUS[@]}"; do
  log_file="${E2E_LOG_DIR:-/tmp}/5-deploy-${sku}.log"

  deploy_one "$sku" \
    > >(tee "$log_file") 2>&1 &
  PIDS+=($!)
done

DEPLOY_FAILED=0
for pid in "${PIDS[@]}"; do
  if ! wait "$pid"; then DEPLOY_FAILED=1; fi
done
if [[ "$DEPLOY_FAILED" -ne 0 ]]; then
  err "One or more deployments failed."
  exit 1
fi

for sku in "${SKUS[@]}"; do
  ep_name=$(sku_endpoint_name "$sku")
  info "$sku deployment:"
  az ml online-deployment show --name "qwen35-vllm" --endpoint-name "$ep_name" \
    --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" -o json
done

_step_end

_step_end
