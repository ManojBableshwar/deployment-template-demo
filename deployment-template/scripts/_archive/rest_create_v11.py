"""Create model v11 via dataplane API reusing v10's blob + DT v4."""
import requests, subprocess, json, time

token = subprocess.check_output(
    ["az", "account", "get-access-token", "--resource", "https://ml.azure.com",
     "--query", "accessToken", "-o", "tsv"]
).decode().strip()

BASE = "https://cert-eastus2.experiments.azureml.net/mferp/managementfrontend"
SUB = "75703df0-38f9-4e2e-8328-45f6fc810286"
RG = "mabables-rg"
REG = "mabables-reg-feb26"
API = "2021-10-01-dataplanepreview"
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

# Get v10's properties
url10 = f"{BASE}/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.MachineLearningServices/registries/{REG}/models/Qwen35-08B/versions/10"
r = requests.get(url10, params={"api-version": API}, headers=headers)
p10 = r.json()["properties"]
print(f"v10 modelUri: {p10['modelUri'][:80]}")
print(f"v10 DT: {json.dumps(p10.get('defaultDeploymentTemplate'))}")

# Create v11 with v10's blob + DT v4
body = {
    "properties": {
        "modelType": "custom_model",
        "modelUri": p10["modelUri"],
        "description": "Qwen3.5-0.8B with DT v4 (pre-built env)",
        "isAnonymous": False,
        "defaultDeploymentTemplate": {
            "assetId": "azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/4"
        },
        "tags": p10.get("tags", {}),
    }
}
url11 = url10.replace("/versions/10", "/versions/11")
print(f"\nCreating v11...")
r2 = requests.put(url11, params={"api-version": API}, headers=headers, json=body)
print(f"Status: {r2.status_code}")
print(f"Response: {r2.text[:500]}")

if r2.status_code == 202:
    loc = r2.headers.get("Location", "")
    for i in range(20):
        time.sleep(5)
        p = requests.get(loc, headers={"Authorization": f"Bearer {token}"})
        pd = p.json() if p.status_code == 200 else {}
        print(f"  Poll {i+1}: keys={list(pd.keys())[:5]}")
        if "status" not in pd:
            break
        if pd.get("status") in ("Succeeded", "Failed", "Canceled"):
            break

time.sleep(5)
print("\nVerifying v11...")
r3 = requests.get(url11, params={"api-version": API}, headers={"Authorization": f"Bearer {token}"})
if r3.status_code == 200:
    p11 = r3.json()["properties"]
    print(f"DT: {json.dumps(p11.get('defaultDeploymentTemplate'))}")
    print(f"modelUri: {p11.get('modelUri', 'none')[:100]}")
else:
    print(f"v11 GET: {r3.status_code} {r3.text[:300]}")
