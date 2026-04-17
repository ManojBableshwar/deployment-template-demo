"""Create an Azure ML registry using the Python SDK."""

import os
import sys

from azure.ai.ml import MLClient
from azure.ai.ml.entities import (
    Registry,
    RegistryRegionDetails,
    SystemCreatedAcrAccount,
    SystemCreatedStorageAccount,
)
from azure.identity import DefaultAzureCredential

SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "75703df0-38f9-4e2e-8328-45f6fc810286")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "mabables-rg")
REGISTRY_NAME = os.environ.get("AZUREML_REGISTRY", "mabables-reg-feb26")
REGISTRY_LOCATION = os.environ.get("REGISTRY_LOCATION", "eastus2")


def main():
    print(f"[INFO] Creating registry '{REGISTRY_NAME}' in '{REGISTRY_LOCATION}'…")

    credential = DefaultAzureCredential()

    # MLClient at subscription level for registry creation
    ml_client = MLClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        resource_group_name=RESOURCE_GROUP,
    )

    registry = Registry(
        name=REGISTRY_NAME,
        location=REGISTRY_LOCATION,
        replication_locations=[
            RegistryRegionDetails(
                location=REGISTRY_LOCATION,
                acr_config=[SystemCreatedAcrAccount(acr_account_sku="Premium")],
                storage_config=SystemCreatedStorageAccount(
                    storage_account_hns=False,
                    storage_account_type="Standard_LRS",
                ),
            ),
        ],
    )

    result = ml_client.registries.begin_create(registry=registry).result()
    print(f"[INFO] Registry created: {result.name}")
    print(f"       Location:  {result.location}")
    print(f"       ID:        {result.id}")


if __name__ == "__main__":
    main()
