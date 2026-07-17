#!/usr/bin/env bash
# ==============================================================================
# env.sh -- Shared environment variables for the Truss+vLLM PoC scripts
# ==============================================================================

# -- Paths ---------------------------------------------------------------------
# Layout: <REPO_ROOT>/truss-poc/vllm/scripts/env.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"          # truss-poc/vllm
TRUSS_POC_ROOT="$(cd "$POC_ROOT/.." && pwd)"      # truss-poc
REPO_ROOT="$(cd "$TRUSS_POC_ROOT/.." && pwd)"     # repo root

export POC_ROOT SCRIPT_DIR REPO_ROOT TRUSS_POC_ROOT

# -- Azure Infrastructure (same as main project) -------------------------------
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-75703df0-38f9-4e2e-8328-45f6fc810286}"
export RESOURCE_GROUP="${RESOURCE_GROUP:-mabables-rg}"
export AZUREML_WORKSPACE="${AZUREML_WORKSPACE:-mabables-feb2026}"
export WORKSPACE_LOCATION="${WORKSPACE_LOCATION:-eastus2}"
export AZUREML_REGISTRY="${AZUREML_REGISTRY:-mabables-reg-feb26}"
export REGISTRY_LOCATION="${REGISTRY_LOCATION:-eastus2}"

# -- Truss+vLLM PoC Resource Names (distinct from the transformers sample) ------
export TRUSS_MODEL_NAME="${TRUSS_MODEL_NAME:-truss-vllm-qwen35}"
export TRUSS_MODEL_VERSION="${TRUSS_MODEL_VERSION:-1}"
export TRUSS_ENVIRONMENT_NAME="${TRUSS_ENVIRONMENT_NAME:-truss-vllm-server}"
export TRUSS_ENVIRONMENT_VERSION="${TRUSS_ENVIRONMENT_VERSION:-1}"
export TRUSS_TEMPLATE_NAME="${TRUSS_TEMPLATE_NAME:-truss-vllm-qwen35-tp1}"
export TRUSS_TEMPLATE_VERSION="${TRUSS_TEMPLATE_VERSION:-1}"
export TRUSS_ENDPOINT_NAME="${TRUSS_ENDPOINT_NAME:-truss-vllm-qwen35-a100}"
export TRUSS_DEPLOYMENT_NAME="${TRUSS_DEPLOYMENT_NAME:-truss-vllm-dep}"
export TRUSS_INSTANCE_TYPE="${TRUSS_INSTANCE_TYPE:-Standard_NC24ads_A100_v4}"

# -- vLLM base image (same as the repo references) -----------------------------
export VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai:latest}"

# -- Model source (local weights from existing repo — uploaded via azcopy) -----
export MODEL_ARTIFACTS_DIR="${MODEL_ARTIFACTS_DIR:-$REPO_ROOT/azureml-deployment-templates/models/qwen--qwen3-5-0-8b/model-artifacts}"

# -- YAML paths ----------------------------------------------------------------
export YAML_DIR="$POC_ROOT/yaml"
export DOCKER_DIR="$POC_ROOT/docker"
export TRUSS_MODEL_DIR="$POC_ROOT/truss-model"

# -- Logging -------------------------------------------------------------------
export LOG_TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
export LOG_DIR="$POC_ROOT/logs/$LOG_TIMESTAMP"

# -- Helpers -------------------------------------------------------------------
info() { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }

ensure_log_dir() {
  mkdir -p "$LOG_DIR"
  echo "$LOG_DIR"
}

log_cmd() {
  # Usage: log_cmd <logfile> <command...>
  local logfile="$1"; shift
  ensure_log_dir > /dev/null
  "$@" 2>&1 | tee "$LOG_DIR/$logfile"
  return "${PIPESTATUS[0]}"
}
