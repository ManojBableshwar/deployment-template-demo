#!/usr/bin/env bash
#
# create-registry.sh — Create an Azure ML registry via CLI
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../env.sh"

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; exit 1; }

# Ensure logged in
az account show &>/dev/null || error "Not logged in. Run 'az login' first."

# Set subscription
info "Setting subscription to $SUBSCRIPTION_ID"
az account set --subscription "$SUBSCRIPTION_ID"

# Create resource group if it doesn't exist
info "Ensuring resource group '$RESOURCE_GROUP' exists in '$REGISTRY_LOCATION'…"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$REGISTRY_LOCATION" \
  --only-show-errors \
  -o none 2>/dev/null || true

# Create the registry
info "Creating Azure ML registry '$AZUREML_REGISTRY' in '$REGISTRY_LOCATION'…"
az ml registry create \
  --name "$AZUREML_REGISTRY" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$REGISTRY_LOCATION" \
  --only-show-errors

info "Registry '$AZUREML_REGISTRY' created successfully."
az ml registry show --name "$AZUREML_REGISTRY" --resource-group "$RESOURCE_GROUP" -o table
