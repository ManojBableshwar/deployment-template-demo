#!/usr/bin/env bash
# Step 2 (REST API): Create deployment template in the Azure ML registry
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"
_step_start "Step 2: Create deployment template"

TOKEN=$(az account get-access-token --query accessToken -o tsv)

ENVIRONMENT_ASSET_ID="azureml://registries/${AZUREML_REGISTRY}/environments/${ENVIRONMENT_NAME}/versions/${ENVIRONMENT_VERSION}"

# -- Check if deployment template already exists ------------------------------
EXISTING=$(curl -s -o /dev/null -w "%{http_code}" \
  "${REGISTRY_BASE}/deploymentTemplates/${TEMPLATE_NAME}/versions/${TEMPLATE_VERSION}?api-version=${API_VERSION_PREVIEW}" \
  -H "Authorization: Bearer $TOKEN")

if [[ "$EXISTING" == "200" ]]; then
  info "Deployment template '$TEMPLATE_NAME' v$TEMPLATE_VERSION already exists -- skipping creation."
else
  info "Creating deployment template '$TEMPLATE_NAME' v$TEMPLATE_VERSION via REST API..."

  RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
    "${REGISTRY_BASE}/deploymentTemplates/${TEMPLATE_NAME}/versions/${TEMPLATE_VERSION}?api-version=${API_VERSION_PREVIEW}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "properties": {
        "description": "Generic vLLM deployment template for single-GPU models (v'"$TEMPLATE_VERSION"')",
        "deploymentTemplateType": "managed",
        "environment": "'"$ENVIRONMENT_ASSET_ID"'",
        "defaultInstanceType": "Standard_NC40ads_H100_v5",
        "allowedInstanceTypes": [
          "Standard_NC24ads_A100_v4",
          "Standard_NC40ads_H100_v5"
        ],
        "instanceCount": 1,
        "scoringPort": 8000,
        "scoringPath": "/v1",
        "modelMountPath": "/opt/ml/model",
        "environmentVariables": {
          "VLLM_TENSOR_PARALLEL_SIZE": "1",
          "VLLM_MAX_MODEL_LEN": "131072",
          "VLLM_GPU_MEMORY_UTILIZATION": "0.9",
          "VLLM_MAX_NUM_SEQS": "48",
          "HF_HUB_OFFLINE": "1",
          "TRANSFORMERS_OFFLINE": "1",
          "VLLM_NO_USAGE_STATS": "1",
          "HF_HOME": "/tmp/hf_cache"
        },
        "requestSettings": {
          "requestTimeoutMs": 90000,
          "maxConcurrentRequestsPerInstance": 250
        },
        "livenessProbe": {
          "initialDelay": 600,
          "period": 10,
          "timeout": 10,
          "successThreshold": 1,
          "scheme": "http",
          "method": "GET",
          "path": "/health",
          "port": 8000
        },
        "readinessProbe": {
          "initialDelay": 600,
          "period": 10,
          "timeout": 10,
          "successThreshold": 1,
          "scheme": "http",
          "method": "GET",
          "path": "/health",
          "port": 8000
        }
      }
    }')

  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | head -n -1)

  if [[ "$HTTP_CODE" =~ ^2 ]]; then
    info "Deployment template created (HTTP $HTTP_CODE)."
  else
    echo "ERROR: HTTP $HTTP_CODE"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    exit 1
  fi
fi

info "Showing details:"
TOKEN=$(az account get-access-token --query accessToken -o tsv)
curl -sS \
  "${REGISTRY_BASE}/deploymentTemplates/${TEMPLATE_NAME}/versions/${TEMPLATE_VERSION}?api-version=${API_VERSION_PREVIEW}" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -m json.tool

_step_end
