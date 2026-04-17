"""Step 4: Create a managed online endpoint in the Azure ML workspace."""

import json
import os

from azure.ai.ml import MLClient
from azure.ai.ml.entities import ManagedOnlineEndpoint
from azure.identity import DefaultAzureCredential

SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "75703df0-38f9-4e2e-8328-45f6fc810286")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "mabables-rg")
WORKSPACE_NAME = os.environ.get("AZUREML_WORKSPACE", "mabables-feb2026")
ENDPOINT_NAME = os.environ.get("ENDPOINT_NAME", "qwen35-endpoint")


def main():
    credential = DefaultAzureCredential()
    ml_client = MLClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        resource_group_name=RESOURCE_GROUP,
        workspace_name=WORKSPACE_NAME,
    )

    # Check if endpoint already exists
    try:
        existing = ml_client.online_endpoints.get(ENDPOINT_NAME)
        print(f"[INFO] Endpoint '{ENDPOINT_NAME}' already exists — skipping creation.")
        print(f"       Scoring URI: {existing.scoring_uri}")
        print(f"       State:       {existing.provisioning_state}")
    except Exception:
        endpoint = ManagedOnlineEndpoint(
            name=ENDPOINT_NAME,
            auth_mode="key",
            description="Online endpoint for Qwen3.5-0.8B served via vLLM",
        )

        print(f"[INFO] Creating endpoint '{ENDPOINT_NAME}'…")
        result = ml_client.online_endpoints.begin_create_or_update(endpoint).result()
        print(f"[INFO] Endpoint created: {result.name}")
        print(f"       Scoring URI: {result.scoring_uri}")
        print(f"       State:       {result.provisioning_state}")

    # Show details
    endpoint = ml_client.online_endpoints.get(ENDPOINT_NAME)
    print("\n[RESULT]")
    print(json.dumps(endpoint._to_dict(), indent=2, default=str))


if __name__ == "__main__":
    main()
