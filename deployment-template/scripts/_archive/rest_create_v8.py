"""Create model v8 in registry via dataplane REST API, reusing v5's blob storage."""
import requests
import subprocess
import json
import sys
import time

token = subprocess.check_output(
    ["az", "account", "get-access-token", "--resource", "https://ml.azure.com",
     "--query", "accessToken", "-o", "tsv"]
).decode().strip()

SUB = "75703df0-38f9-4e2e-8328-45f6fc810286"
RG = "mabables-rg"
REG = "mabables-reg-feb26"
BASE = "https://cert-eastus2.experiments.azureml.net/mferp/managementfrontend"
API = "2021-10-01-dataplanepreview"
MODEL_URI = "https://6ec5159fc0c.blob.core.windows.net/mabables-r-a17e9c18-78df-50ac-a916-cf649e061049/LocalUpload/model-artifacts-qwen35/model-artifacts"
DT_ASSET = "azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/3"

url = f"{BASE}/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.MachineLearningServices/registries/{REG}/models/Qwen35-08B/versions/8"
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

body = {
    "properties": {
        "modelType": "custom_model",
        "description": "Qwen3.5-0.8B with DT linked (reuses v5 blob)",
        "modelUri": MODEL_URI,
        "tags": {"source": "huggingface", "hf_model_id": "Qwen/Qwen3.5-0.8B"},
        "defaultDeploymentTemplate": {"assetId": DT_ASSET}
    }
}

print(f"PUT {url}")
print(f"Body: {json.dumps(body, indent=2)}")
r = requests.put(url, params={"api-version": API}, headers=headers, json=body)
print(f"\nStatus: {r.status_code}")
print(f"Headers: {dict(r.headers)}")
if r.text:
    print(f"Response: {json.dumps(r.json(), indent=2)}")
else:
    print("Empty response body")

if r.status_code == 202:
    loc = r.headers.get("Location", "")
    print(f"\nPolling Location: {loc}")
    # Poll until complete
    for i in range(30):
        time.sleep(10)
        poll = requests.get(loc, headers={"Authorization": f"Bearer {token}"})
        print(f"Poll {i+1}: status={poll.status_code}")
        if poll.status_code == 200:
            data = poll.json()
            status = data.get("status", data.get("properties", {}).get("provisioningState", "?"))
            print(f"  Provisioning: {status}")
            if status in ("Succeeded", "Completed"):
                break

# Verify
print("\n\nVerifying v8...")
get_url = f"{BASE}/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.MachineLearningServices/registries/{REG}/models/Qwen35-08B/versions/8"
r2 = requests.get(get_url, params={"api-version": API}, headers=headers)
if r2.status_code == 200:
    p = r2.json().get("properties", {})
    print(f"modelUri: {p.get('modelUri', 'N/A')}")
    print(f"DT: {json.dumps(p.get('defaultDeploymentTemplate', 'N/A'))}")
else:
    print(f"GET failed: {r2.status_code} {r2.text[:200]}")
