"""Create a new model version via dataplane POST, reusing v5's blob + setting DT."""
import requests, subprocess, json

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

# 1. Get v5's full properties to reuse
url5 = f"{BASE}/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.MachineLearningServices/registries/{REG}/models/Qwen35-08B/versions/5"
r = requests.get(url5, params={"api-version": API}, headers=headers)
v5 = r.json()
props5 = v5["properties"]
print(f"v5 modelUri: {props5['modelUri'][:80]}...")
print(f"v5 flavors: {list(props5.get('flavors', {}).keys())}")

# 2. POST to create v9 with v5's modelUri + DT
version = "9"
url_create = f"{BASE}/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.MachineLearningServices/registries/{REG}/models/Qwen35-08B/versions/{version}"
body = {
    "properties": {
        "modelType": props5.get("modelType", "custom_model"),
        "modelUri": props5["modelUri"],
        "description": "Qwen3.5-0.8B with deployment template (reused v5 artifacts)",
        "isAnonymous": False,
        "defaultDeploymentTemplate": {
            "assetId": "azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/3"
        },
        "tags": props5.get("tags", {}),
        "properties": props5.get("properties", {}),
    }
}

print(f"\n3. PUT (create) v{version}...")
print(f"   Body DT: {json.dumps(body['properties']['defaultDeploymentTemplate'])}")
r2 = requests.put(url_create, params={"api-version": API}, headers=headers, json=body)
print(f"   Status: {r2.status_code}")
try:
    resp = r2.json()
    print(f"   Response: {json.dumps(resp, indent=2)[:800]}")
except:
    print(f"   Response text: {r2.text[:500]}")

# 3. If 202, poll
if r2.status_code == 202:
    import time
    loc = r2.headers.get("Location", "")
    print(f"\n4. Polling: {loc[:100]}")
    for i in range(20):
        time.sleep(5)
        poll = requests.get(loc, headers={"Authorization": f"Bearer {token}"})
        if poll.status_code == 200:
            pd = poll.json()
            if isinstance(pd, dict) and "status" in pd:
                print(f"   Poll {i+1}: {pd['status']}")
                if pd["status"] in ("Succeeded", "Failed", "Canceled"):
                    if pd.get("error"):
                        print(f"   Error: {json.dumps(pd['error'])[:300]}")
                    break
            elif isinstance(pd, dict) and "assetId" in pd:
                print(f"   Poll {i+1}: assetId present (no status)")
                # This is actually the completed response for model create
                break
        else:
            print(f"   Poll {i+1}: HTTP {poll.status_code}")
            if poll.status_code >= 400:
                print(f"   Error: {poll.text[:300]}")
                break

# 4. Verify v9
print(f"\n5. Verify v{version}...")
import time; time.sleep(5)
url9 = url_create
r3 = requests.get(url9, params={"api-version": API}, headers=headers)
if r3.status_code == 200:
    p9 = r3.json()["properties"]
    print(f"   DT: {json.dumps(p9.get('defaultDeploymentTemplate'))}")
    print(f"   modelUri: {p9.get('modelUri', 'none')[:100]}")
else:
    print(f"   v{version} not found: {r3.status_code}")
    print(f"   {r3.text[:300]}")
