"""Test setting DT on existing registry model v5 via dataplane, with detailed verification."""
import requests
import subprocess
import json
import time

token = subprocess.check_output(
    ["az", "account", "get-access-token", "--resource", "https://ml.azure.com",
     "--query", "accessToken", "-o", "tsv"]
).decode().strip()

BASE = "https://cert-eastus2.experiments.azureml.net/mferp/managementfrontend"
SUB = "75703df0-38f9-4e2e-8328-45f6fc810286"
RG = "mabables-rg"
REG = "mabables-reg-feb26"
API = "2021-10-01-dataplanepreview"

url = f"{BASE}/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.MachineLearningServices/registries/{REG}/models/Qwen35-08B/versions/5"
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

# GET current state
print("1. GET current state...")
r = requests.get(url, params={"api-version": API}, headers=headers)
data = r.json()
props = data["properties"]
print(f"  DT before: {json.dumps(props.get('defaultDeploymentTemplate'))}")

# PUT with DT - use the FULL existing body
body = {"properties": dict(props)}
body["properties"]["defaultDeploymentTemplate"] = {
    "assetId": "azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/3"
}
# Remove read-only / null fields that might cause issues
for key in ["provisioningState", "originAssetId", "intellectualProperty", "system_metadata"]:
    body["properties"].pop(key, None)

print(f"\n2. PUT with DT...")
print(f"  DT in body: {json.dumps(body['properties']['defaultDeploymentTemplate'])}")
r2 = requests.put(url, params={"api-version": API}, headers=headers, json=body)
print(f"  Status: {r2.status_code}")
print(f"  Location: {r2.headers.get('Location', 'none')[:200]}")
if r2.text:
    try:
        print(f"  Response: {json.dumps(r2.json(), indent=2)[:500]}")
    except:
        print(f"  Response text: {r2.text[:500]}")

# Poll the async operation if 202
if r2.status_code == 202:
    loc = r2.headers.get("Location", "")
    timeout = r2.headers.get("x-ms-async-operation-timeout", "")
    retry = r2.headers.get("Retry-After", "10")
    print(f"\n3. Polling async operation...")
    print(f"  Timeout: {timeout}")
    print(f"  Retry-After: {retry}")
    
    for i in range(12):
        time.sleep(int(retry) if retry.isdigit() else 10)
        poll = requests.get(loc, headers={"Authorization": f"Bearer {token}"})
        print(f"  Poll {i+1}: status={poll.status_code}")
        if poll.status_code == 200:
            pd = poll.json()
            if isinstance(pd, dict):
                print(f"    Data keys: {list(pd.keys())[:10]}")
                if "status" in pd:
                    print(f"    status: {pd['status']}")
                    if pd["status"] in ("Succeeded", "Completed", "Failed", "Canceled"):
                        if pd["status"] == "Failed":
                            print(f"    Error: {json.dumps(pd.get('error','?'))}")
                        break
        elif poll.status_code == 204:
            print("    Operation completed (204)")
            break
        elif poll.status_code >= 400:
            print(f"    Error: {poll.text[:200]}")
            break

# Final verification
print(f"\n4. GET after update...")
time.sleep(5)
r3 = requests.get(url, params={"api-version": API}, headers=headers)
props3 = r3.json()["properties"]
print(f"  DT after: {json.dumps(props3.get('defaultDeploymentTemplate'))}")
print(f"  Description: {props3.get('description')}")
