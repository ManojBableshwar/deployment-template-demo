#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# env.sh — Shared environment variables for Azure ML scripts
#
# Sources user config from configs/e2e-config.sh (or E2E_CONFIG env var).
# Variables from the config file take precedence; anything unset falls back
# to the defaults below.
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR_ENV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR_ENV="$(cd "$SCRIPT_DIR_ENV/.." && pwd)"

# Source user config if available
CONFIG_FILE="${E2E_CONFIG:-$ROOT_DIR_ENV/configs/e2e-config.sh}"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

# ── Defaults (only set if not already exported by config) ────────────────────
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-75703df0-38f9-4e2e-8328-45f6fc810286}"
export RESOURCE_GROUP="${RESOURCE_GROUP:-mabables-rg}"

export AZUREML_WORKSPACE="${AZUREML_WORKSPACE:-mabables-feb2026}"
export WORKSPACE_LOCATION="${WORKSPACE_LOCATION:-eastus2}"

export AZUREML_REGISTRY="${AZUREML_REGISTRY:-mabables-reg-feb26}"
export REGISTRY_LOCATION="${REGISTRY_LOCATION:-eastus2}"

export MODEL_NAME="${MODEL_NAME:-Qwen35-08B}"
export MODEL_VERSION="${MODEL_VERSION:-1}"
export HF_MODEL_ID="${HF_MODEL_ID:-Qwen/Qwen3.5-0.8B}"

export ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-vllm-qwen35}"
export ENVIRONMENT_VERSION="${ENVIRONMENT_VERSION:-1}"
export VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai:latest}"

export TEMPLATE_NAME="${TEMPLATE_NAME:-vllm-1gpu-h100}"
export TEMPLATE_VERSION="${TEMPLATE_VERSION:-1}"

export ENDPOINT_NAME="${ENDPOINT_NAME:-qwen35-endpoint}"
export DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-qwen35-vllm}"

export API_VERSION="${API_VERSION:-2024-10-01}"
export API_VERSION_PREVIEW="${API_VERSION_PREVIEW:-2025-04-01-preview}"

# Helper: ARM base URLs
export REGISTRY_BASE="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/registries/${AZUREML_REGISTRY}"
export WORKSPACE_BASE="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/workspaces/${AZUREML_WORKSPACE}"
