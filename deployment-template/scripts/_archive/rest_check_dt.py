"""Quick check: does v5 have DT now? Also print poll content."""
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

url = f"{BASE}/subscriptions/{SUB}/resourceGroups/{RG}/providers/Microsoft.MachineLearningServices/registries/{REG}/models/Qwen35-08B/versions/5"
headers = {"Authorization": f"Bearer {token}"}

r = requests.get(url, params={"api-version": API}, headers=headers)
props = r.json()["properties"]
print(f"v5 DT: {json.dumps(props.get('defaultDeploymentTemplate'))}")

# Also check the poll URL
poll_url = "https://eastus2.api.azureml.ms/assetstore/v1.0/operations/86vBZPg5vnKWod17JQN_Ke6Z1s14uTtR4_FfBXSn1g4"
r2 = requests.get(poll_url, headers=headers)
print(f"Poll response: {json.dumps(r2.json(), indent=2)[:500]}")

# Also check v6 (tiny, had DT)
url6 = url.replace("/versions/5", "/versions/6")
r6 = requests.get(url6, params={"api-version": API}, headers=headers)
p6 = r6.json()["properties"]
print(f"v6 DT: {json.dumps(p6.get('defaultDeploymentTemplate'))}")
