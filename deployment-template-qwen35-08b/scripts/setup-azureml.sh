#!/usr/bin/env bash
#
# setup-azureml.sh -- Install and configure the Azure ML CLI extension and Python SDK
#
set -euo pipefail

REQUIRED_CLI_VERSION="2.0.0"
ML_EXT_NAME="ml"
PIP_PACKAGE="azure-ai-ml"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*"; exit 1; }

command_exists() { command -v "$1" &>/dev/null; }

# ---------------------------------------------------------------------------
# 1. Check / install Azure CLI
# ---------------------------------------------------------------------------
install_azure_cli() {
    if command_exists az; then
        local ver
        ver=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
        info "Azure CLI already installed (version $ver)"
    else
        info "Azure CLI not found -- installing..."
        case "$(uname -s)" in
            Darwin)
                if command_exists brew; then
                    brew update && brew install azure-cli
                else
                    error "Homebrew not found. Install Homebrew first: https://brew.sh"
                fi
                ;;
            Linux)
                curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
                ;;
            *)
                error "Unsupported OS. Install Azure CLI manually: https://aka.ms/installazurecli"
                ;;
        esac
    fi
}

# ---------------------------------------------------------------------------
# 2. Install / upgrade the Azure ML CLI extension (v2)
# ---------------------------------------------------------------------------
install_ml_extension() {
    local installed
    installed=$(az extension list --query "[?name=='$ML_EXT_NAME'].version" -o tsv 2>/dev/null || true)

    if [[ -n "$installed" ]]; then
        info "Azure ML CLI extension already installed (version $installed) -- upgrading..."
        az extension update --name "$ML_EXT_NAME" --only-show-errors 2>/dev/null || true
    else
        info "Installing Azure ML CLI extension..."
        az extension add --name "$ML_EXT_NAME" --only-show-errors
    fi

    # Verify
    local new_ver
    new_ver=$(az extension list --query "[?name=='$ML_EXT_NAME'].version" -o tsv 2>/dev/null)
    info "Azure ML CLI extension version: $new_ver"
}

# ---------------------------------------------------------------------------
# 3. Install the Azure ML Python SDK
# ---------------------------------------------------------------------------
install_python_sdk() {
    if ! command_exists python3; then
        warn "python3 not found -- skipping Python SDK installation"
        return
    fi

    local pip_cmd="pip3"
    command_exists pip3 || pip_cmd="python3 -m pip"

    info "Installing / upgrading $PIP_PACKAGE Python package..."
    $pip_cmd install --upgrade "$PIP_PACKAGE" --quiet

    local sdk_ver
    sdk_ver=$(python3 -c "import azure.ai.ml; print(azure.ai.ml.__version__)" 2>/dev/null || echo "unknown")
    info "azure-ai-ml SDK version: $sdk_ver"
}

# ---------------------------------------------------------------------------
# 4. Verify deployment-template support
# ---------------------------------------------------------------------------
verify_deployment_template_support() {
    info "Verifying deployment-template CLI support..."
    if az ml deployment-template --help &>/dev/null; then
        info "✔ 'az ml deployment-template' subgroup is available"
    else
        warn "✘ 'az ml deployment-template' subgroup not found -- your CLI extension may be too old"
    fi

    if command_exists python3; then
        info "Verifying deployment-template Python SDK support..."
        if python3 -c "from azure.ai.ml.entities import DeploymentTemplate" 2>/dev/null; then
            info "✔ DeploymentTemplate entity class is importable"
        else
            warn "✘ DeploymentTemplate not found in azure.ai.ml.entities"
        fi
    fi
}

# ---------------------------------------------------------------------------
# 5. Print summary
# ---------------------------------------------------------------------------
print_summary() {
    echo
    info "=========================================="
    info " Setup complete"
    info "=========================================="
    echo
    echo "  CLI:  az ml deployment-template --help"
    echo "  SDK:  python3 -c \"from azure.ai.ml.entities import DeploymentTemplate\""
    echo
    echo "  Next steps:"
    echo "    1. Log in:               az login"
    echo "    2. Set subscription:     az account set -s <subscription>"
    echo "    3. Create a template:    az ml deployment-template create --file template.yml --registry-name <registry>"
    echo
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    info "Setting up Azure ML tooling for deployment templates..."
    echo

    install_azure_cli
    install_ml_extension
    install_python_sdk
    verify_deployment_template_support
    print_summary
}

main "$@"
