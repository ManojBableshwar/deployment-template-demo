#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# e2e-config.sh — User-overridable configuration for E2E runs
#
# Copy this file and modify values as needed. Pass it to the e2e runner:
#   ./scripts/run-e2e-cli.sh --config my-config.sh
#
# Any variable left unset here falls back to the default in env.sh.
# ──────────────────────────────────────────────────────────────────────────────

# ── Azure Subscription & Resource Group ──────────────────────────────────────
export SUBSCRIPTION_ID="75703df0-38f9-4e2e-8328-45f6fc810286"
export RESOURCE_GROUP="mabables-rg"

# ── Workspace ────────────────────────────────────────────────────────────────
export AZUREML_WORKSPACE="mabables-feb2026"
export WORKSPACE_LOCATION="eastus2"

# ── Registry ─────────────────────────────────────────────────────────────────
export AZUREML_REGISTRY="mabables-reg-feb26"
export REGISTRY_LOCATION="eastus2"

# ── Model ────────────────────────────────────────────────────────────────────
export MODEL_NAME="Qwen35-08B"
export MODEL_VERSION="21"
export HF_MODEL_ID="Qwen/Qwen3.5-0.8B"

# ── Environment ──────────────────────────────────────────────────────────────────
export ENVIRONMENT_NAME="vllm-qwen35"
export ENVIRONMENT_VERSION="21"
export VLLM_IMAGE="vllm/vllm-openai:latest"

# ── Deployment Template ──────────────────────────────────────────────────────
export TEMPLATE_NAME="vllm-1gpu-h100"
export TEMPLATE_VERSION="21"

# ── Online Endpoint & Deployment ─────────────────────────────────────────────
export ENDPOINT_NAME="qwen35-endpoint"
export DEPLOYMENT_NAME="qwen35-vllm"

# ── REST API versions ────────────────────────────────────────────────────────
export API_VERSION="2024-10-01"
export API_VERSION_PREVIEW="2025-04-01-preview"
