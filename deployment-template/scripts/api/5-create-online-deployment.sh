#!/usr/bin/env bash
# Step 5 (REST API): Create a managed online deployment
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

TOKEN=$(az account get-access-token --query accessToken -o tsv)

MODEL_ASSET_ID="azureml://registries/${AZUREML_REGISTRY}/models/${MODEL_NAME}/versions/${MODEL_VERSION}"
ENVIRONMENT_ASSET_ID="azureml://registries/${AZUREML_REGISTRY}/environments/${ENVIRONMENT_NAME}/versions/${ENVIRONMENT_VERSION}"

info "Creating deployment '$DEPLOYMENT_NAME' under endpoint '$ENDPOINT_NAME' via REST API…"

RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
  "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}/deployments/${DEPLOYMENT_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "location": "'"$WORKSPACE_LOCATION"'",
    "properties": {
      "model": "'"$MODEL_ASSET_ID"'",
      "environmentId": "'"$ENVIRONMENT_ASSET_ID"'",
      "instanceType": "Standard_NC40ads_H100_v5",
      "scaleSettings": {
        "scaleType": "Default"
      },
      "requestSettings": {
        "requestTimeout": "PT90S",
        "maxConcurrentRequestsPerInstance": 10
      },
      "livenessProbe": {
        "initialDelay": "PT600S",
        "period": "PT10S",
        "timeout": "PT10S"
      },
      "readinessProbe": {
        "initialDelay": "PT600S",
        "period": "PT10S",
        "timeout": "PT10S"
      },
      "environmentVariables": {
        "VLLM_SERVED_MODEL_NAME": "Qwen3.5-0.8B"
      },
      "modelMountPath": "/opt/ml/model"
    },
    "sku": {
      "name": "Default",
      "capacity": 1
    }
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_CODE" =~ ^2 ]]; then
  info "Deployment created (HTTP $HTTP_CODE)."
  echo "$BODY" | python3 -m json.tool
else
  echo "ERROR: HTTP $HTTP_CODE"
  echo "$BODY" | python3 -m json.tool
  exit 1
fi

# Update traffic to 100%
info "Updating endpoint traffic to route 100% to '$DEPLOYMENT_NAME'…"
curl -s -X PATCH \
  "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "properties": {
      "traffic": {
        "'"$DEPLOYMENT_NAME"'": 100
      }
    }
  }' | python3 -m json.tool
