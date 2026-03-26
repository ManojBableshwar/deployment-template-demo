"""Step 1: Create vLLM environment in the Azure ML registry."""

import json
import os

from azure.ai.ml import MLClient
from azure.ai.ml.entities import Environment
from azure.identity import DefaultAzureCredential

SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "75703df0-38f9-4e2e-8328-45f6fc810286")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "mabables-rg")
REGISTRY_NAME = os.environ.get("AZUREML_REGISTRY", "mabables-reg-feb26")
ENVIRONMENT_NAME = os.environ.get("ENVIRONMENT_NAME", "vllm-qwen35")
ENVIRONMENT_VERSION = os.environ.get("ENVIRONMENT_VERSION", "11")
VLLM_IMAGE = os.environ.get("VLLM_IMAGE", "vllm/vllm-openai:latest")


def main():
    credential = DefaultAzureCredential()
    ml_client = MLClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        resource_group_name=RESOURCE_GROUP,
        registry_name=REGISTRY_NAME,
    )

    env = Environment(
        name=ENVIRONMENT_NAME,
        version=ENVIRONMENT_VERSION,
        image=VLLM_IMAGE,
        description="vLLM OpenAI-compatible inference server for Qwen3.5 models",
        tags={"framework": "vllm", "model_family": "qwen3.5"},
    )

    result = ml_client.environments.create_or_update(env)
    print(f"[INFO] Environment created: {result.name} v{result.version}")
    print(f"       Image: {result.image}")
    print(f"       ID:    {result.id}")
    print()
    print("[RESULT]")
    print(json.dumps(result._to_dict(), indent=2, default=str))


if __name__ == "__main__":
    main()
