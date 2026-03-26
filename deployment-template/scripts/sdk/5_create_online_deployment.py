"""Step 5: Create a managed online deployment under the endpoint."""

import json
import os

from azure.ai.ml import MLClient
from azure.ai.ml.entities import (
    ManagedOnlineDeployment,
    OnlineRequestSettings,
    ProbeSettings,
)
from azure.identity import DefaultAzureCredential

SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "75703df0-38f9-4e2e-8328-45f6fc810286")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "mabables-rg")
WORKSPACE_NAME = os.environ.get("AZUREML_WORKSPACE", "mabables-feb2026")
REGISTRY_NAME = os.environ.get("AZUREML_REGISTRY", "mabables-reg-feb26")
MODEL_NAME = os.environ.get("MODEL_NAME", "Qwen35-08B")
MODEL_VERSION = os.environ.get("MODEL_VERSION", "13")
ENVIRONMENT_NAME = os.environ.get("ENVIRONMENT_NAME", "vllm-qwen35")
ENVIRONMENT_VERSION = os.environ.get("ENVIRONMENT_VERSION", "11")
ENDPOINT_NAME = os.environ.get("ENDPOINT_NAME", "qwen35-endpoint")
DEPLOYMENT_NAME = os.environ.get("DEPLOYMENT_NAME", "qwen35-vllm")


def main():
    credential = DefaultAzureCredential()
    ml_client = MLClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        resource_group_name=RESOURCE_GROUP,
        workspace_name=WORKSPACE_NAME,
    )

    model_id = (
        f"azureml://registries/{REGISTRY_NAME}"
        f"/models/{MODEL_NAME}/versions/{MODEL_VERSION}"
    )
    environment_id = (
        f"azureml://registries/{REGISTRY_NAME}"
        f"/environments/{ENVIRONMENT_NAME}/versions/{ENVIRONMENT_VERSION}"
    )

    deployment = ManagedOnlineDeployment(
        name=DEPLOYMENT_NAME,
        endpoint_name=ENDPOINT_NAME,
        model=model_id,
        environment=environment_id,
        instance_type="Standard_NC40ads_H100_v5",
        instance_count=1,
        model_mount_path="/opt/ml/model",
        environment_variables={
            "VLLM_SERVED_MODEL_NAME": "Qwen3.5-0.8B",
        },
        request_settings=OnlineRequestSettings(
            request_timeout_ms=90000,
            max_concurrent_requests_per_instance=10,
        ),
        liveness_probe=ProbeSettings(
            initial_delay=600,
            period=10,
            timeout=10,
        ),
        readiness_probe=ProbeSettings(
            initial_delay=600,
            period=10,
            timeout=10,
        ),
    )

    print(f"[INFO] Creating deployment '{DEPLOYMENT_NAME}' under '{ENDPOINT_NAME}'…")
    result = ml_client.online_deployments.begin_create_or_update(deployment).result()
    print(f"[INFO] Deployment created: {result.name}")
    print(f"       Instance type: {result.instance_type}")
    print(f"       State:         {result.provisioning_state}")
    print("\n[RESULT] Deployment:")
    print(json.dumps(result._to_dict(), indent=2, default=str))

    # Route all traffic to this deployment
    endpoint = ml_client.online_endpoints.get(ENDPOINT_NAME)
    endpoint.traffic = {DEPLOYMENT_NAME: 100}
    ep_result = ml_client.online_endpoints.begin_create_or_update(endpoint).result()
    print(f"\n[INFO] Traffic set to 100% for '{DEPLOYMENT_NAME}'.")
    print("\n[RESULT] Endpoint traffic:")
    print(json.dumps(ep_result._to_dict(), indent=2, default=str))


if __name__ == "__main__":
    main()
