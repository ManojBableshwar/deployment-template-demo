#!/usr/bin/env bash
# Step 5: Create online deployments (TP×SKU-aware, parallel)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"

read -ra TPS <<< "${E2E_TPS:-1}"
read -ra SKUS <<< "${E2E_SKUS:-a100 h100}"
_step_start "Step 5: Create online deployments (TP=${TPS[*]} × SKU=${SKUS[*]})"

DESIRED_MODEL="azureml://registries/${AZUREML_REGISTRY}/models/${MODEL_NAME}/versions/${MODEL_VERSION}"

deploy_one() {
  local tp="$1" sku="$2"
  local ep_name dep_name yaml_file
  ep_name=$(tp_sku_endpoint_name "$tp" "$sku")
  dep_name=$(tp_sku_deployment_name "$tp")
  yaml_file="$YAML_DIR/deployment-tp${tp}-${sku}.yml"

  if existing_json=$(az ml online-deployment show \
        --name "$dep_name" --endpoint-name "$ep_name" \
        --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" \
        -o json 2>/dev/null); then
    existing_model=$(printf '%s' "$existing_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('model',''))")
    provisioning_state=$(printf '%s' "$existing_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('provisioning_state',''))")

    if [[ "$existing_model" == "$DESIRED_MODEL" && "$provisioning_state" == "Succeeded" ]]; then
      info "[tp${tp}-${sku}] Already exists with desired model -- skipping."
      return 0
    fi
    info "[tp${tp}-${sku}] Stale or failed (state=$provisioning_state). Recreating..."
    # Zero traffic before deleting (AzureML blocks deletion of deployments with traffic)
    az ml online-endpoint update \
      --name "$ep_name" \
      --traffic "$dep_name=0" \
      --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" \
      2>/dev/null || true
    az ml online-deployment delete \
      --name "$dep_name" --endpoint-name "$ep_name" \
      --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" \
      --yes
  fi

  info "[tp${tp}-${sku}] Creating deployment..."
  az ml online-deployment create \
    --file "$yaml_file" \
    --workspace-name "$AZUREML_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --all-traffic
  info "[tp${tp}-${sku}] Created."
}

# Build TP×SKU combos
COMBOS=()
for tp in "${TPS[@]}"; do
  for sku in "${SKUS[@]}"; do
    COMBOS+=("${tp}:${sku}")
  done
done

info "Deploying in parallel for: ${COMBOS[*]}"

PIDS=()
for combo in "${COMBOS[@]}"; do
  tp="${combo%%:*}"
  sku="${combo##*:}"
  log_file="${E2E_LOG_DIR:-/tmp}/5-deploy-tp${tp}-${sku}.log"

  deploy_one "$tp" "$sku" \
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

for combo in "${COMBOS[@]}"; do
  tp="${combo%%:*}"
  sku="${combo##*:}"
  ep_name=$(tp_sku_endpoint_name "$tp" "$sku")
  dep_name=$(tp_sku_deployment_name "$tp")
  info "tp${tp}-${sku} deployment:"
  az ml online-deployment show --name "$dep_name" --endpoint-name "$ep_name" \
    --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" -o json
done

# -- Capture container logs immediately after deployment (before they rotate) --
info "Capturing container startup logs (TP confirmation)..."
for combo in "${COMBOS[@]}"; do
  tp="${combo%%:*}"
  sku="${combo##*:}"
  ep_name=$(tp_sku_endpoint_name "$tp" "$sku")
  dep_name=$(tp_sku_deployment_name "$tp")
  startup_log="${E2E_LOG_DIR:-/tmp}/5-startup-tp${tp}-${sku}.log"

  info "[tp${tp}-${sku}] Fetching container logs..."
  if az ml online-deployment get-logs \
       --name "$dep_name" --endpoint-name "$ep_name" \
       --workspace-name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" \
       --lines 5000 > "$startup_log" 2>&1; then
    # Extract and display the TP confirmation line from vLLM startup
    tp_line=$(grep -i 'tensor_parallel_size\|VLLM_TENSOR_PARALLEL_SIZE\|number_of_gpus\|ParallelConfig\|TP size' "$startup_log" 2>/dev/null | head -5 || true)
    if [[ -n "$tp_line" ]]; then
      info "[tp${tp}-${sku}] TP confirmation from container logs:"
      echo "$tp_line"
    else
      info "[tp${tp}-${sku}] No explicit TP line found in startup logs (may have rotated). Full logs saved to $startup_log"
    fi
  else
    err "[tp${tp}-${sku}] Failed to fetch container logs."
  fi
done

_step_end
