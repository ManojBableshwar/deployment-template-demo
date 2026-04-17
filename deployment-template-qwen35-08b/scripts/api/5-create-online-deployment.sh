#!/usr/bin/env bash
# Step 5 (REST API): Create a managed online deployment
#
# The deployment is MINIMAL -- just model + instance type.  The deployment
# template linked to the model provides: environment, probes, scoring
# port/path, env vars, request settings, and model mount path.
# Setting modelMountPath, environment, or probes here will conflict with
# the deployment template or cause "curated env" errors.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }

az account set --subscription "$SUBSCRIPTION_ID"
_step_start "Step 5: Create online deployment"

TOKEN=$(az account get-access-token --query accessToken -o tsv)

MODEL_ASSET_ID="azureml://registries/${AZUREML_REGISTRY}/models/${MODEL_NAME}/versions/${MODEL_VERSION}"

# -- Check if deployment already exists and is healthy ------------------------
EXISTING=$(curl -s \
  "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}/deployments/${DEPLOYMENT_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN")

EXISTING_STATE=$(echo "$EXISTING" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('provisioningState',''))" 2>/dev/null || true)
EXISTING_MODEL=$(echo "$EXISTING" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('model',''))" 2>/dev/null || true)

if [[ "$EXISTING_STATE" == "Succeeded" && "$EXISTING_MODEL" == "$MODEL_ASSET_ID" ]]; then
  info "Deployment '$DEPLOYMENT_NAME' already exists with desired model and succeeded state -- skipping creation."
elif [[ -n "$EXISTING_STATE" && "$EXISTING_STATE" != "" ]]; then
  info "Deployment '$DEPLOYMENT_NAME' exists but is stale or failed (state=$EXISTING_STATE, model=$EXISTING_MODEL). Deleting..."

  # Set traffic to 0 first
  curl -s -X PATCH \
    "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}?api-version=${API_VERSION}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"properties":{"traffic":{"'"$DEPLOYMENT_NAME"'":0}}}' >/dev/null 2>&1 || true

  # Delete stale deployment
  curl -sS -X DELETE \
    "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}/deployments/${DEPLOYMENT_NAME}?api-version=${API_VERSION}" \
    -H "Authorization: Bearer $TOKEN" >/dev/null 2>&1

  # Wait for deletion
  info "Waiting for deployment deletion..."
  for i in $(seq 1 40); do
    TOKEN=$(az account get-access-token --query accessToken -o tsv)
    DEL_STATE=$(curl -s -o /dev/null -w "%{http_code}" \
      "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}/deployments/${DEPLOYMENT_NAME}?api-version=${API_VERSION}" \
      -H "Authorization: Bearer $TOKEN")
    if [[ "$DEL_STATE" == "404" ]]; then
      info "Deployment deleted."
      break
    fi
    sleep 15
  done

  EXISTING_STATE=""  # Force creation below
fi

if [[ "$EXISTING_STATE" != "Succeeded" ]]; then
  info "Creating deployment '$DEPLOYMENT_NAME' under endpoint '$ENDPOINT_NAME' via REST API..."
  TOKEN=$(az account get-access-token --query accessToken -o tsv)

  RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
    "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}/deployments/${DEPLOYMENT_NAME}?api-version=${API_VERSION}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "location": "'"$WORKSPACE_LOCATION"'",
      "properties": {
        "model": "'"$MODEL_ASSET_ID"'",
        "instanceType": "Standard_NC40ads_H100_v5"
      },
      "sku": {
        "name": "Default",
        "capacity": 1
      }
    }')

  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | head -n -1)

  if [[ "$HTTP_CODE" =~ ^2 ]]; then
    info "Deployment creation initiated (HTTP $HTTP_CODE)."
  else
    echo "ERROR: HTTP $HTTP_CODE"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    exit 1
  fi

  # Wait for deployment to reach Succeeded state
  info "Waiting for deployment provisioning (polling every 30s, up to 30 min)..."
  MAX_WAIT=1800
  INTERVAL=30
  ELAPSED=0
  while (( ELAPSED < MAX_WAIT )); do
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
    TOKEN=$(az account get-access-token --query accessToken -o tsv)
    DEP_JSON=$(curl -s \
      "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}/deployments/${DEPLOYMENT_NAME}?api-version=${API_VERSION}" \
      -H "Authorization: Bearer $TOKEN")
    DEP_STATE=$(echo "$DEP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('provisioningState',''))" 2>/dev/null || true)
    info "Provisioning state: $DEP_STATE (${ELAPSED}s elapsed)"
    if [[ "$DEP_STATE" == "Succeeded" ]]; then
      info "Deployment provisioned successfully."
      break
    elif [[ "$DEP_STATE" == "Failed" || "$DEP_STATE" == "Canceled" ]]; then
      echo "ERROR: Deployment provisioning $DEP_STATE"
      echo "$DEP_JSON" | python3 -m json.tool 2>/dev/null || echo "$DEP_JSON"
      exit 1
    fi
  done

  if (( ELAPSED >= MAX_WAIT )); then
    echo "ERROR: Timed out waiting for deployment provisioning after ${MAX_WAIT}s"
    exit 1
  fi
fi

# -- Update traffic to 100% --------------------------------------------------
info "Updating endpoint traffic to route 100% to '$DEPLOYMENT_NAME'..."
TOKEN=$(az account get-access-token --query accessToken -o tsv)
curl -sS -X PATCH \
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

info "Showing deployment details:"
TOKEN=$(az account get-access-token --query accessToken -o tsv)
curl -sS \
  "${WORKSPACE_BASE}/onlineEndpoints/${ENDPOINT_NAME}/deployments/${DEPLOYMENT_NAME}?api-version=${API_VERSION}" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -m json.tool

_step_end
