"""Create an Azure ML workspace using the Python SDK."""

import os

from azure.ai.ml import MLClient
from azure.ai.ml.entities import Workspace
from azure.identity import DefaultAzureCredential

SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "75703df0-38f9-4e2e-8328-45f6fc810286")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "mabables-rg")
WORKSPACE_NAME = os.environ.get("AZUREML_WORKSPACE", "mabables-feb2026")
WORKSPACE_LOCATION = os.environ.get("WORKSPACE_LOCATION", "eastus2")


def main():
    print(f"[INFO] Creating workspace '{WORKSPACE_NAME}' in '{WORKSPACE_LOCATION}'…")

    credential = DefaultAzureCredential()

    ml_client = MLClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        resource_group_name=RESOURCE_GROUP,
    )

    workspace = Workspace(
        name=WORKSPACE_NAME,
        location=WORKSPACE_LOCATION,
    )

    result = ml_client.workspaces.begin_create(workspace=workspace).result()
    print(f"[INFO] Workspace created: {result.name}")
    print(f"       Location:  {result.location}")
    print(f"       ID:        {result.id}")


if __name__ == "__main__":
    main()
