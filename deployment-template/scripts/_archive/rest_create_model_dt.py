"""Create model v7 in registry directly via dataplane REST API with DT, pointing to existing registry blob."""
import requests
import subprocess
import json

# Get Azure CLI token for registry dataplane
token = subprocess.check_output(
    ["az", "account", "get-access-token", "--resource", "https://ml.azure.com", "--query", "accessToken", "-o", "tsv"]
).decode().strip()

SUB = "75703df0-38f9-4e2e-8328-45f6fc810286"
RG = "mabables-rg"
REGISTRY = "mabables-reg-feb26"

# The dataplane API uses the same ARM URL pattern but api-version=2021-10-01-dataplanepreview
# But that's not a registered ARM API version. The SDK sends this to the dataplane endpoint URL.
# Let me check what the SDK actually sends by looking at the cert-eastus2.experiments.azureml.net endpoint.

# From SDK source, registry model versions use:
# URL: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.MachineLearningServices/registries/{reg}/models/{name}/versions/{version}
# api-version: 2021-10-01-dataplanepreview
# Base URL: cert-eastus2.experiments.azureml.net (the primaryRegionResourceProviderUri)

base_url = "https://cert-eastus2.experiments.azureml.net/mferp/managementfrontend"
url = f"{base_url}/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.MachineLearningServices/registries/{REGISTRY}/models/Qwen35-08B/versions/7"

# Model payload - no modelUri, just DT. Let service allocate storage.
body = {
    "properties": {
        "modelType": "custom_model",
        "description": "Qwen3.5-0.8B with deployment template (full artifacts)",
        "tags": {
            "source": "huggingface",
            "hf_model_id": "Qwen/Qwen3.5-0.8B",
            "parameters": "0.8B",
            "framework": "transformers",
            "architecture": "qwen3_5"
        },
        "defaultDeploymentTemplate": {
            "assetId": "azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/3"
        }
    }
}

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}

print(f"PUT {url}")
print(f"api-version=2021-10-01-dataplanepreview")
print(f"Body: {json.dumps(body, indent=2)}")
print()

resp = requests.put(
    url,
    params={"api-version": "2021-10-01-dataplanepreview"},
    headers=headers,
    json=body
)

print(f"Status: {resp.status_code}")
print(f"Response: {json.dumps(resp.json(), indent=2)}")
