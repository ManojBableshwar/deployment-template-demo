#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# env.sh -- Shared environment variables for Azure ML deployment template scripts
#
# All resource names are derived from HF_MODEL_ID (e.g. "Qwen/Qwen3.5-0.8B").
# Set HF_MODEL_ID before sourcing, or pass --hf-model to the runner.
# ------------------------------------------------------------------------------

SCRIPT_DIR_ENV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AZUREML_DT_ROOT="$(cd "$SCRIPT_DIR_ENV/.." && pwd)"
TEMPLATES_DIR="$AZUREML_DT_ROOT/templates"

# -- HF Model ID → slug function ----------------------------------------------
# Converts "Qwen/Qwen3.5-0.8B" → "qwen--qwen3-5-0-8b"
#   - lowercase
#   - / → --
#   - . → -
#   - strip anything not [a-z0-9-]
#   - collapse multiple hyphens
#   - trim leading/trailing hyphens
hf_slug() {
  echo "$1" | tr '[:upper:]' '[:lower:]' \
    | sed 's|/|--|g' \
    | sed 's|\.|-|g' \
    | sed 's|[^a-z0-9-]||g' \
    | sed 's|-\{2,\}|--|g' \
    | sed 's|^-||;s|-$||'
}

# Truncate a name to fit Azure limits, appending a short hash if needed.
# Usage: truncate_name <name> <max_len>
truncate_name() {
  local name="$1" max_len="${2:-32}"
  if (( ${#name} <= max_len )); then
    echo "$name"
  else
    # Keep first (max_len - 5) chars + 4-char hash
    local hash
    hash=$(printf '%s' "$name" | md5sum 2>/dev/null || md5 -q -s "$name" 2>/dev/null || echo "0000")
    hash="${hash:0:4}"
    local keep=$(( max_len - 5 ))
    echo "${name:0:$keep}-${hash}"
  fi
}

# -- Require HF_MODEL_ID ------------------------------------------------------
if [[ -z "${HF_MODEL_ID:-}" ]]; then
  echo "[ERROR] HF_MODEL_ID is not set." >&2
  echo "  Usage: HF_MODEL_ID=Qwen/Qwen3.5-0.8B source env.sh" >&2
  echo "  Or:    run-e2e-cli.sh --hf-model Qwen/Qwen3.5-0.8B" >&2
  exit 1
fi
export HF_MODEL_ID

# -- Derive model slug and paths ----------------------------------------------
export MODEL_SLUG="$(hf_slug "$HF_MODEL_ID")"
export MODEL_ROOT="$AZUREML_DT_ROOT/models/$MODEL_SLUG"

# -- Propagate ASSET_VERSION to unset per-asset versions (before config.sh) ----
# Priority: per-asset CLI flag > ASSET_VERSION > config.sh > default (1)
export ASSET_VERSION="${ASSET_VERSION:-}"
export MODEL_VERSION="${MODEL_VERSION:-${ASSET_VERSION:-}}"
export ENVIRONMENT_VERSION="${ENVIRONMENT_VERSION:-${ASSET_VERSION:-}}"
export TEMPLATE_VERSION="${TEMPLATE_VERSION:-${ASSET_VERSION:-}}"

# Source model-specific overrides (versions, image, etc.) if they exist
# config.sh uses conditional exports, so CLI-set values survive.
if [[ -f "$MODEL_ROOT/config.sh" ]]; then
  source "$MODEL_ROOT/config.sh"
fi

# Model data paths
export MODEL_DIR="$MODEL_ROOT/model-artifacts"
export MODEL_CONFIG="$MODEL_DIR/config.json"
export YAML_DIR="$MODEL_ROOT/yaml"
export LOG_BASE="$MODEL_ROOT/logs"

# -- Azure infrastructure (not model-specific) --------------------------------
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-75703df0-38f9-4e2e-8328-45f6fc810286}"
export RESOURCE_GROUP="${RESOURCE_GROUP:-mabables-rg}"

export AZUREML_WORKSPACE="${AZUREML_WORKSPACE:-mabables-feb2026}"
export WORKSPACE_LOCATION="${WORKSPACE_LOCATION:-eastus2}"

export AZUREML_REGISTRY="${AZUREML_REGISTRY:-mabables-reg-feb26}"
export REGISTRY_LOCATION="${REGISTRY_LOCATION:-eastus2}"

# -- Derived resource names (all from MODEL_SLUG) -----------------------------
export MODEL_NAME="${MODEL_NAME:-$MODEL_SLUG}"
export MODEL_VERSION="${MODEL_VERSION:-1}"

export ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-vllm-server}"
export ENVIRONMENT_VERSION="${ENVIRONMENT_VERSION:-1}"
export VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai:latest}"

export TEMPLATE_NAME="${TEMPLATE_NAME:-vllm-${MODEL_SLUG}}"
export TEMPLATE_VERSION="${TEMPLATE_VERSION:-1}"

export DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-$(truncate_name "${MODEL_SLUG}-vllm" 32)}"

# Per-SKU instance types (override via --sku in the runner)
export INSTANCE_TYPE_A100="${INSTANCE_TYPE_A100:-Standard_NC24ads_A100_v4}"
export INSTANCE_TYPE_H100="${INSTANCE_TYPE_H100:-Standard_NC40ads_H100_v5}"

# Per-SKU endpoint names (32 char Azure limit)
export ENDPOINT_NAME_A100="${ENDPOINT_NAME_A100:-$(truncate_name "${MODEL_SLUG}-a100" 32)}"
export ENDPOINT_NAME_H100="${ENDPOINT_NAME_H100:-$(truncate_name "${MODEL_SLUG}-h100" 32)}"

export API_VERSION="${API_VERSION:-2024-10-01}"
export API_VERSION_PREVIEW="${API_VERSION_PREVIEW:-2025-04-01-preview}"

# Helper: ARM base URLs
export REGISTRY_BASE="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/registries/${AZUREML_REGISTRY}"
export WORKSPACE_BASE="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/workspaces/${AZUREML_WORKSPACE}"

# -- Hydrate YAML templates → model yaml/ dir ---------------------------------
# Generates concrete YAML files from shared templates for the current model.
# Safe to call repeatedly (overwrites generated files).
hydrate_yaml() {
  local tmpl_dir="$TEMPLATES_DIR/yaml"
  local out_dir="$YAML_DIR"
  mkdir -p "$out_dir/docker"

  # Copy docker files (not templated)
  cp "$tmpl_dir/docker/Dockerfile" "$out_dir/docker/Dockerfile"
  cp "$tmpl_dir/docker/vllm-run.sh" "$out_dir/docker/vllm-run.sh"
  chmod +x "$out_dir/docker/vllm-run.sh"

  # Build a sed script file for all substitutions (avoids eval + special-char issues)
  local sed_script
  sed_script=$(mktemp)

  local vars=(
    "HF_MODEL_ID"
    "MODEL_NAME" "MODEL_VERSION"
    "ENVIRONMENT_NAME" "ENVIRONMENT_VERSION"
    "TEMPLATE_NAME" "TEMPLATE_VERSION"
    "DEPLOYMENT_NAME"
    "INSTANCE_TYPE_A100" "INSTANCE_TYPE_H100"
    "ENDPOINT_NAME_A100" "ENDPOINT_NAME_H100"
    "AZUREML_REGISTRY"
  )

  for v in "${vars[@]}"; do
    # Use | as sed delimiter to avoid issues with / in values (e.g. HF_MODEL_ID)
    printf 's|${%s}|%s|g\n' "$v" "${!v}" >> "$sed_script"
  done

  for tmpl in "$tmpl_dir"/*.tmpl.yml; do
    [[ -f "$tmpl" ]] || continue
    local base
    base="$(basename "$tmpl" .tmpl.yml)"
    local out="$out_dir/${base}.yml"
    sed -f "$sed_script" "$tmpl" > "$out"
  done

  rm -f "$sed_script"
}

# -- Timing helpers -----------------------------------------------------------
_STEP_START_EPOCH=""
_step_start() {
  _STEP_START_EPOCH=$(date +%s)
  printf '\033[1;36m[START]\033[0m %s -- %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}
_step_end() {
  local end_epoch=$(date +%s)
  local elapsed=$(( end_epoch - _STEP_START_EPOCH ))
  local mins=$(( elapsed / 60 ))
  local secs=$(( elapsed % 60 ))
  printf '\033[1;32m[DONE]\033[0m  %s -- elapsed %dm %ds\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$mins" "$secs"
}
