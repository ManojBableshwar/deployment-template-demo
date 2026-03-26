#!/usr/bin/env bash
# Step 2 (REST API): Create deployment template in the Azure ML registry
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

TOKEN=$(az account get-access-token --query accessToken -o tsv)

ENVIRONMENT_ASSET_ID="azureml://registries/${AZUREML_REGISTRY}/environments/${ENVIRONMENT_NAME}/versions/${ENVIRONMENT_VERSION}"

info "Creating deployment template '$TEMPLATE_NAME' v$TEMPLATE_VERSION via REST API…"

RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
  "${REGISTRY_BASE}/deploymentTemplates/${TEMPLATE_NAME}/versions/${TEMPLATE_VERSION}?api-version=${API_VERSION_PREVIEW}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "properties": {
      "description": "Generic vLLM deployment template for single-GPU models on H100",
      "environment": "'"$ENVIRONMENT_ASSET_ID"'",
      "instanceType": "Standard_NC40ads_H100_v5",
      "instanceCount": 1,
      "scoringPort": 5001,
      "scoringPath": "/v1",
      "modelMountPath": "/opt/ml/model",
      "environmentVariables": {
        "VLLM_MODEL_NAME": "/opt/ml/model",
        "VLLM_TENSOR_PARALLEL_SIZE": "1",
        "VLLM_MAX_MODEL_LEN": "131072",
        "VLLM_GPU_MEMORY_UTILIZATION": "0.9",
        "HF_HOME": "/tmp/hf_cache"
      },
      "requestSettings": {
        "requestTimeoutMs": 90000,
        "maxConcurrentRequestsPerInstance": 10
      },
      "livenessProbe": {
        "initialDelay": 600,
        "period": 10,
        "timeout": 10
      },
      "readinessProbe": {
        "initialDelay": 600,
        "period": 10,
        "timeout": 10
      }
    }
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" =~ ^2 ]]; then
  info "Deployment template created (HTTP $HTTP_CODE)."
  echo "$BODY" | python3 -m json.tool
else
  echo "ERROR: HTTP $HTTP_CODE"
  echo "$BODY" | python3 -m json.tool
  exit 1
fi
