#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# config.sh — Configuration for BYOC (Bring Your Own Container) E2E demo
# ──────────────────────────────────────────────────────────────────────────────
export SUBSCRIPTION_ID="75703df0-38f9-4e2e-8328-45f6fc810286"
export RESOURCE_GROUP="mabables-rg"
export AZUREML_WORKSPACE="mabables-feb2026"
export AZUREML_REGISTRY="mabables-reg-feb26"
export WORKSPACE_LOCATION="eastus2"

export MODEL_NAME="Qwen35-08B"
export MODEL_VERSION="5"
export HF_MODEL_ID="Qwen/Qwen3.5-0.8B"

export ENVIRONMENT_NAME="vllm-qwen35"
export ENVIRONMENT_VERSION="11"

export ENDPOINT_NAME="qwen35-endpoint"
export DEPLOYMENT_NAME="byoc-vllm"

export INSTANCE_TYPE="Standard_NC40ads_H100_v5"
