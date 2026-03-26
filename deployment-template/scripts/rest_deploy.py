"""
Deploy model v13 using settings from Deployment Template v6.

Demonstrates the DT value prop: the DT defines the complete deployment recipe
(environment, instance type, env vars, probes, scoring config). This script
reads the DT from the model, extracts all settings, and constructs the
deployment automatically via ARM REST API.

Model v13 has DT v6 → env v11 (Dockerfile-based, runit+nginx).

NOTE: As of March 2026, this FAILS with ModelPresetNotFound due to a
service-side bug in CreatePresetDeploymentFlow.
"""
import json
import subprocess
import sys
import urllib.request
import urllib.error
import ssl

SUBSCRIPTION_ID = "75703df0-38f9-4e2e-8328-45f6fc810286"
RESOURCE_GROUP = "mabables-rg"
WORKSPACE = "mabables-feb2026"
ENDPOINT_NAME = "qwen35-endpoint"
DEPLOYMENT_NAME = "qwen35-vllm"
REGISTRY_NAME = "mabables-reg-feb26"
API_VERSION = "2024-10-01"

MODEL_NAME = "Qwen35-08B"
MODEL_VERSION = "13"

# ── Step 1: Read model to get DT reference ───────────────────────────────────
print(f"Step 1: Reading model {MODEL_NAME}/v{MODEL_VERSION}...", flush=True)
model_result = subprocess.run(
    ["az", "ml", "model", "show",
     "--name", MODEL_NAME, "--version", MODEL_VERSION,
     "--registry-name", REGISTRY_NAME, "-o", "json"],
    capture_output=True, text=True
)
model = json.loads(model_result.stdout)
dt_asset_id = model.get("default_deployment_template", {}).get("asset_id", "")
print(f"  Model: {model['name']} v{model['version']}", flush=True)
print(f"  DT reference: {dt_asset_id}", flush=True)

if not dt_asset_id:
    print("ERROR: Model has no deployment template reference", flush=True)
    sys.exit(1)

# ── Step 2: Read DT settings ────────────────────────────────────────────────
import re
dt_match = re.search(r"deploymentTemplates/([^/]+)/versions/(\d+)", dt_asset_id)
DT_NAME, DT_VERSION = dt_match.group(1), dt_match.group(2)

print(f"\nStep 2: Reading deployment template {DT_NAME}/v{DT_VERSION}...", flush=True)
dt_result = subprocess.run(
    ["az", "ml", "deployment-template", "show",
     "--name", DT_NAME, "--version", DT_VERSION,
     "--registry-name", REGISTRY_NAME, "-o", "json"],
    capture_output=True, text=True
)
dt = json.loads(dt_result.stdout)
print(f"  Environment: {dt['environmentId']}", flush=True)
print(f"  Instance type: {dt['defaultInstanceType']}", flush=True)
print(f"  Scoring: port {dt.get('scoringPort')}, path {dt.get('scoringPath')}", flush=True)
print(f"  Model mount: {dt.get('modelMountPath')}", flush=True)
print(f"  Env vars: {list(dt.get('environmentVariables', {}).keys())}", flush=True)

# ── Step 3: Map DT → deployment body ────────────────────────────────────────
MODEL_REF = f"azureml://registries/{REGISTRY_NAME}/models/{MODEL_NAME}/versions/{MODEL_VERSION}"

# Merge DT env vars with deployment-specific overrides
env_vars = dict(dt.get("environmentVariables", {}))
env_vars["VLLM_SERVED_MODEL_NAME"] = "Qwen3.5-0.8B"  # deployment-specific

deployment_body = {
    "location": "eastus2",
    "sku": {"name": "Default", "capacity": dt.get("instanceCount", 1)},
    "properties": {
        "endpointComputeType": "Managed",
        "model": MODEL_REF,
        "environmentId": dt["environmentId"],
        "instanceType": dt["defaultInstanceType"],
        "environmentVariables": env_vars,
        "requestSettings": {
            "requestTimeout": dt.get("requestSettings", {}).get("requestTimeout", "PT1M30S"),
            "maxConcurrentRequestsPerInstance": dt.get("requestSettings", {}).get("maxConcurrentRequestsPerInstance", 10),
        },
        "livenessProbe": {
            "initialDelay": dt.get("livenessProbe", {}).get("initialDelay", "PT10M"),
            "period": dt.get("livenessProbe", {}).get("period", "PT10S"),
            "timeout": dt.get("livenessProbe", {}).get("timeout", "PT10S"),
            "failureThreshold": 30,
            "successThreshold": 1,
        },
        "readinessProbe": {
            "initialDelay": dt.get("readinessProbe", {}).get("initialDelay", "PT10M"),
            "period": dt.get("readinessProbe", {}).get("period", "PT10S"),
            "timeout": dt.get("readinessProbe", {}).get("timeout", "PT10S"),
            "failureThreshold": 30,
            "successThreshold": 1,
        },
    },
}

print(f"\nStep 2: Constructed deployment from DT settings", flush=True)
print(f"  Model: {MODEL_REF}", flush=True)
print(f"  Environment: {dt['environmentId']}", flush=True)
print(f"  Instance: {dt['defaultInstanceType']}", flush=True)

# ── Step 3: Deploy via ARM REST API ─────────────────────────────────────────
print(f"\nStep 3: Creating deployment via REST API...", flush=True)
token_result = subprocess.run(
    ["az", "account", "get-access-token", "--query", "accessToken", "-o", "tsv"],
    capture_output=True, text=True
)
token = token_result.stdout.strip()

url = (
    f"https://management.azure.com/subscriptions/{SUBSCRIPTION_ID}"
    f"/resourceGroups/{RESOURCE_GROUP}"
    f"/providers/Microsoft.MachineLearningServices"
    f"/workspaces/{WORKSPACE}"
    f"/onlineEndpoints/{ENDPOINT_NAME}"
    f"/deployments/{DEPLOYMENT_NAME}"
    f"?api-version={API_VERSION}"
)

ctx = ssl.create_default_context()
req = urllib.request.Request(
    url,
    data=json.dumps(deployment_body).encode("utf-8"),
    headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    },
    method="PUT",
)

try:
    with urllib.request.urlopen(req, context=ctx) as resp:
        body = json.loads(resp.read())
        print(f"Status: {resp.status}", flush=True)
        print(f"Provisioning state: {body.get('properties', {}).get('provisioningState')}", flush=True)
        print(json.dumps(body, indent=2)[:2000], flush=True)
except urllib.error.HTTPError as e:
    error_body = e.read().decode("utf-8")
    print(f"HTTP Error: {e.code}", flush=True)
    print(f"Response: {error_body[:2000]}", flush=True)
    sys.exit(1)

print("\nDeployment creation submitted successfully!", flush=True)
print("It will take ~10-20 minutes to provision. Check status with:", flush=True)
print(f"  az ml online-deployment show --name {DEPLOYMENT_NAME} --endpoint-name {ENDPOINT_NAME} -w {WORKSPACE} -g {RESOURCE_GROUP}", flush=True)
