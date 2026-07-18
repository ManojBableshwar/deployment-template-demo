#!/usr/bin/env bash
# ==============================================================================
# env.sh -- Shared environment variables for Truss PoC deployment scripts
# ==============================================================================

# -- Paths ---------------------------------------------------------------------
# Layout: <REPO_ROOT>/truss-poc/transformers/scripts/env.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"          # truss-poc/transformers
TRUSS_POC_ROOT="$(cd "$POC_ROOT/.." && pwd)"      # truss-poc
REPO_ROOT="$(cd "$TRUSS_POC_ROOT/.." && pwd)"     # repo root

export POC_ROOT SCRIPT_DIR REPO_ROOT TRUSS_POC_ROOT

# -- Azure Infrastructure (REDACTED for public repo) ---------------------------
# Real IDs are NOT committed. SUBSCRIPTION_ID is auto-detected from your `az login`.
# Set the rest via environment before running, e.g.:
#   export RESOURCE_GROUP=... AZUREML_WORKSPACE=... AZUREML_REGISTRY=...
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id -o tsv 2>/dev/null)}"
export RESOURCE_GROUP="${RESOURCE_GROUP:-<your-resource-group>}"
export AZUREML_WORKSPACE="${AZUREML_WORKSPACE:-<your-workspace>}"
export WORKSPACE_LOCATION="${WORKSPACE_LOCATION:-eastus2}"
export AZUREML_REGISTRY="${AZUREML_REGISTRY:-<your-registry>}"
export REGISTRY_LOCATION="${REGISTRY_LOCATION:-eastus2}"

# -- Truss PoC Resource Names -------------------------------------------------
export TRUSS_MODEL_NAME="${TRUSS_MODEL_NAME:-truss-qwen35-08b}"
export TRUSS_MODEL_VERSION="${TRUSS_MODEL_VERSION:-1}"
export TRUSS_ENVIRONMENT_NAME="${TRUSS_ENVIRONMENT_NAME:-truss-qwen35-server}"
export TRUSS_ENVIRONMENT_VERSION="${TRUSS_ENVIRONMENT_VERSION:-10}"
export TRUSS_TEMPLATE_NAME="${TRUSS_TEMPLATE_NAME:-truss-qwen35-08b-tp1}"
export TRUSS_TEMPLATE_VERSION="${TRUSS_TEMPLATE_VERSION:-1}"
export TRUSS_ENDPOINT_NAME="${TRUSS_ENDPOINT_NAME:-truss-qwen35-08b-a100}"
export TRUSS_DEPLOYMENT_NAME="${TRUSS_DEPLOYMENT_NAME:-truss-qwen35-vllm}"
export TRUSS_INSTANCE_TYPE="${TRUSS_INSTANCE_TYPE:-Standard_NC24ads_A100_v4}"

# -- Model source (local weights from existing repo) ---------------------------
export MODEL_ARTIFACTS_DIR="${MODEL_ARTIFACTS_DIR:-$REPO_ROOT/azureml-deployment-templates/models/qwen--qwen3-5-0-8b/model-artifacts}"

# -- YAML paths ----------------------------------------------------------------
export YAML_DIR="$POC_ROOT/yaml"
export DOCKER_DIR="$POC_ROOT/docker"

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
  # Runs command, tees output to logfile, returns exit code.
  local logfile="$1"; shift
  ensure_log_dir > /dev/null
  "$@" 2>&1 | tee "$LOG_DIR/$logfile"
  return "${PIPESTATUS[0]}"
}
