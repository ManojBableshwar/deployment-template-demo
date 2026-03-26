"""Update model v5 in registry to add DT via the same dataplane API the CLI uses."""
import requests
import subprocess
import json
import sys

# Get token for ml.azure.com scope (dataplane)
token = subprocess.check_output(
    ["az", "account", "get-access-token", "--resource", "https://ml.azure.com", "--query", "accessToken", "-o", "tsv"]
).decode().strip()

SUB = "75703df0-38f9-4e2e-8328-45f6fc810286"
RG = "mabables-rg"
REGISTRY = "mabables-reg-feb26"

base_url = "https://cert-eastus2.experiments.azureml.net/mferp/managementfrontend"
url = f"{base_url}/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.MachineLearningServices/registries/{REGISTRY}/models/Qwen35-08B/versions/5"

# First GET the current model to see what fields exist
headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}

print("GET current model v5...")
resp = requests.get(url, params={"api-version": "2021-10-01-dataplanepreview"}, headers=headers)
print(f"GET Status: {resp.status_code}")
if resp.status_code == 200:
    data = resp.json()
    print(f"Model data keys: {list(data.keys())}")
    props = data.get("properties", {})
    print(f"Properties keys: {list(props.keys())}")
    print(f"modelUri: {props.get('modelUri', 'NOT SET')}")
    print(f"defaultDeploymentTemplate: {props.get('defaultDeploymentTemplate', 'NOT SET')}")
    print(f"Full response:\n{json.dumps(data, indent=2)}")
else:
    print(f"Error: {resp.text}")
    sys.exit(1)

# Now PUT with the DT field added
print("\n\nPUT with defaultDeploymentTemplate...")
# Use the full existing body but add DT
put_body = data.copy()
put_body["properties"]["defaultDeploymentTemplate"] = {
    "assetId": "azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/3"
}

# Remove read-only fields
for key in ["systemData", "id", "name", "type"]:
    put_body.pop(key, None)
props = put_body.get("properties", {})
for key in ["provisioningState"]:
    props.pop(key, None)

print(f"PUT body:\n{json.dumps(put_body, indent=2)}")

resp2 = requests.put(url, params={"api-version": "2021-10-01-dataplanepreview"}, headers=headers, json=put_body)
print(f"\nPUT Status: {resp2.status_code}")
print(f"PUT Response:\n{json.dumps(resp2.json(), indent=2)}")
