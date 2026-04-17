"""Step 5: Create a managed online deployment under the endpoint.

The deployment is MINIMAL — the deployment template attached to the model provides:
environment, probes, scoring port/path, env vars, request settings, model_mount_path.
Only model, endpoint, instance type, and instance count are specified here.

This mirrors the CLI deployment.yml which only sets: model, endpoint, instance_type,
instance_count.
"""

import json
import os

from azure.ai.ml import MLClient
from azure.ai.ml.entities import ManagedOnlineDeployment
from azure.identity import DefaultAzureCredential

SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "75703df0-38f9-4e2e-8328-45f6fc810286")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "mabables-rg")
WORKSPACE_NAME = os.environ.get("AZUREML_WORKSPACE", "mabables-feb2026")
AZUREML_REGISTRY = os.environ.get("AZUREML_REGISTRY", "mabables-reg-feb26")
MODEL_NAME = os.environ.get("MODEL_NAME", "Qwen35-08B")
MODEL_VERSION = os.environ.get("MODEL_VERSION", "40")
ENDPOINT_NAME = os.environ.get("ENDPOINT_NAME", "qwen35-endpoint")
DEPLOYMENT_NAME = os.environ.get("DEPLOYMENT_NAME", "qwen35-vllm")


def _create_deployment(ml_client, model_id):
    """Create a minimal deployment — DT provides environment, probes, env vars, etc."""
    deployment = ManagedOnlineDeployment(
        name=DEPLOYMENT_NAME,
        endpoint_name=ENDPOINT_NAME,
        model=model_id,
        instance_type="Standard_NC40ads_H100_v5",
        instance_count=1,
    )

    print(f"[INFO] Creating deployment '{DEPLOYMENT_NAME}' under '{ENDPOINT_NAME}'…")
    result = ml_client.online_deployments.begin_create_or_update(deployment).result()
    print(f"[INFO] Deployment created: {result.name}")
    print(f"       Instance type: {result.instance_type}")
    print(f"       State:         {result.provisioning_state}")

    # Route all traffic to this deployment
    endpoint = ml_client.online_endpoints.get(ENDPOINT_NAME)
    endpoint.traffic = {DEPLOYMENT_NAME: 100}
    ml_client.online_endpoints.begin_create_or_update(endpoint).result()
    print(f"[INFO] Traffic set to 100% for '{DEPLOYMENT_NAME}'.")


def main():
    credential = DefaultAzureCredential()
    ml_client = MLClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        resource_group_name=RESOURCE_GROUP,
        workspace_name=WORKSPACE_NAME,
    )

    model_id = (
        f"azureml://registries/{AZUREML_REGISTRY}"
        f"/models/{MODEL_NAME}/versions/{MODEL_VERSION}"
    )

    # Check if deployment already exists and is healthy
    try:
        existing = ml_client.online_deployments.get(
            name=DEPLOYMENT_NAME,
            endpoint_name=ENDPOINT_NAME,
        )
        existing_model = getattr(existing, "model", "")
        prov_state = getattr(existing, "provisioning_state", "")

        if existing_model == model_id and prov_state == "Succeeded":
            print(f"[INFO] Deployment '{DEPLOYMENT_NAME}' already exists with desired model and succeeded state — skipping creation.")
        else:
            print(f"[INFO] Deployment '{DEPLOYMENT_NAME}' exists but is stale or failed (state={prov_state}, model={existing_model}). Recreating…")
            # Set traffic to 0 and delete stale deployment
            try:
                endpoint = ml_client.online_endpoints.get(ENDPOINT_NAME)
                endpoint.traffic = {DEPLOYMENT_NAME: 0}
                ml_client.online_endpoints.begin_create_or_update(endpoint).result()
            except Exception:
                pass
            ml_client.online_deployments.begin_delete(
                name=DEPLOYMENT_NAME,
                endpoint_name=ENDPOINT_NAME,
            ).result()
            _create_deployment(ml_client, model_id)
    except Exception:
        _create_deployment(ml_client, model_id)

    # Show details
    result = ml_client.online_deployments.get(
        name=DEPLOYMENT_NAME,
        endpoint_name=ENDPOINT_NAME,
    )
    print("\n[RESULT]")
    print(json.dumps(result._to_dict(), indent=2, default=str))


if __name__ == "__main__":
    main()
