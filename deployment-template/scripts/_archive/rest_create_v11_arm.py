"""Create model v11 via ARM API reusing v10's blob + DT v4."""
import requests, subprocess, json

token = subprocess.check_output(
    ["az", "account", "get-access-token", "--query", "accessToken", "-o", "tsv"]
).decode().strip()

ARM = "https://management.azure.com"
SUB = "75703df0-38f9-4e2e-8328-45f6fc810286"
RG = "mabables-rg"
REG = "mabables-reg-feb26"
API = "2025-04-01-preview"
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

# Get v10's modelUri
base = f"{ARM}/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.MachineLearningServices/registries/{REG}/models/Qwen35-08B"
r10 = requests.get(f"{base}/versions/10", params={"api-version": "2024-10-01"}, headers=headers)
print(f"GET v10: {r10.status_code}")
p10 = r10.json()["properties"]
model_uri = p10["modelUri"]
print(f"v10 modelUri: {model_uri[:100]}")

# Try different API versions for the PUT
for api_ver in ["2025-04-01-preview", "2025-12-01"]:
    body = {
        "properties": {
            "modelType": "custom_model",
            "modelUri": model_uri,
            "description": "Qwen3.5-0.8B with DT v4 (pre-built env)",
            "isAnonymous": False,
            "tags": p10.get("tags", {}),
        }
    }
    print(f"\nPUT v11 with api-version={api_ver}...")
    r = requests.put(f"{base}/versions/11", params={"api-version": api_ver}, headers=headers, json=body)
    print(f"  Status: {r.status_code}")
    resp = r.json()
    if r.status_code in (200, 201):
        rp = resp.get("properties", {})
        print(f"  modelUri: {rp.get('modelUri', 'N/A')[:100]}")
        print(f"  provState: {rp.get('provisioningState')}")
        # Success! Now check if we can deploy from this
        print("  SUCCESS - v11 created via ARM")
        break
    else:
        err = resp.get("error", {})
        print(f"  Error: {err.get('code')}: {err.get('message', '')[:200]}")
        # If version already exists due to previous attempt, delete and retry
        if "already exists" in str(err).lower():
            print("  Deleting existing v11...")
            rd = requests.delete(f"{base}/versions/11", params={"api-version": api_ver}, headers=headers)
            print(f"  Delete: {rd.status_code}")
