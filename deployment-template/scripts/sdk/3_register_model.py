"""Step 3: Download model from HuggingFace and register in Azure ML registry."""

import json
import os
from pathlib import Path

from azure.ai.ml import MLClient
from azure.ai.ml.entities import Model, DefaultDeploymentTemplate
from azure.identity import DefaultAzureCredential

SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "75703df0-38f9-4e2e-8328-45f6fc810286")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "mabables-rg")
REGISTRY_NAME = os.environ.get("AZUREML_REGISTRY", "mabables-reg-feb26")
MODEL_NAME = os.environ.get("MODEL_NAME", "Qwen35-08B")
MODEL_VERSION = os.environ.get("MODEL_VERSION", "13")
HF_MODEL_ID = os.environ.get("HF_MODEL_ID", "Qwen/Qwen3.5-0.8B")
TEMPLATE_NAME = os.environ.get("TEMPLATE_NAME", "vllm-1gpu-h100")
TEMPLATE_VERSION = os.environ.get("TEMPLATE_VERSION", "6")

MODEL_DIR = Path(__file__).resolve().parent.parent.parent.parent / "model-artifacts"


def download_model():
    """Download model from HuggingFace Hub."""
    from huggingface_hub import snapshot_download

    print(f"[INFO] Downloading '{HF_MODEL_ID}' to {MODEL_DIR}…")
    snapshot_download(HF_MODEL_ID, local_dir=str(MODEL_DIR))
    print("[INFO] Download complete.")


def register_model():
    """Register the downloaded model in the Azure ML registry."""
    credential = DefaultAzureCredential()
    ml_client = MLClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        resource_group_name=RESOURCE_GROUP,
        registry_name=REGISTRY_NAME,
    )

    template_asset_id = (
        f"azureml://registries/{REGISTRY_NAME}"
        f"/deploymentTemplates/{TEMPLATE_NAME}/versions/{TEMPLATE_VERSION}"
    )

    model = Model(
        name=MODEL_NAME,
        version=MODEL_VERSION,
        path=str(MODEL_DIR),
        type="custom_model",
        description="Qwen3.5-0.8B — multimodal language model (0.8B params, 262K context)",
        tags={
            "source": "huggingface",
            "hf_model_id": HF_MODEL_ID,
            "parameters": "0.8B",
            "framework": "transformers",
        },
        properties={
            "defaultDeploymentTemplate": template_asset_id,
        },
    )

    print(f"[INFO] Registering model '{MODEL_NAME}' v{MODEL_VERSION}…")
    result = ml_client.models.create_or_update(model)
    print(f"[INFO] Model registered: {result.name} v{result.version}")
    print(f"       ID: {result.id}")
    print("\n[RESULT]")
    print(json.dumps(result._to_dict(), indent=2, default=str))


def main():
    download_model()
    register_model()


if __name__ == "__main__":
    main()
