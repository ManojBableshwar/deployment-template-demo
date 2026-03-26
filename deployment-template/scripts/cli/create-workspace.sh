#!/usr/bin/env bash
#
# create-workspace.sh — Create an Azure ML workspace via CLI
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
info "Ensuring resource group '$RESOURCE_GROUP' exists in '$WORKSPACE_LOCATION'…"
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$WORKSPACE_LOCATION" \
  --only-show-errors \
  -o none 2>/dev/null || true

# Create the workspace
info "Creating Azure ML workspace '$AZUREML_WORKSPACE' in '$WORKSPACE_LOCATION'…"
az ml workspace create \
  --name "$AZUREML_WORKSPACE" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$WORKSPACE_LOCATION" \
  --only-show-errors

info "Workspace '$AZUREML_WORKSPACE' created successfully."
az ml workspace show --name "$AZUREML_WORKSPACE" --resource-group "$RESOURCE_GROUP" -o table
