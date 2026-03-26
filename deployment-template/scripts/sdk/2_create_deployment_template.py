"""Step 2: Create deployment template in the Azure ML registry."""

import json
import os

from azure.ai.ml import MLClient
from azure.ai.ml.entities import DeploymentTemplate
from azure.identity import DefaultAzureCredential

SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "75703df0-38f9-4e2e-8328-45f6fc810286")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "mabables-rg")
REGISTRY_NAME = os.environ.get("AZUREML_REGISTRY", "mabables-reg-feb26")
ENVIRONMENT_NAME = os.environ.get("ENVIRONMENT_NAME", "vllm-qwen35")
ENVIRONMENT_VERSION = os.environ.get("ENVIRONMENT_VERSION", "11")
TEMPLATE_NAME = os.environ.get("TEMPLATE_NAME", "vllm-1gpu-h100")
TEMPLATE_VERSION = os.environ.get("TEMPLATE_VERSION", "6")


def main():
    credential = DefaultAzureCredential()
    ml_client = MLClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        resource_group_name=RESOURCE_GROUP,
        registry_name=REGISTRY_NAME,
    )

    env_id = (
        f"azureml://registries/{REGISTRY_NAME}"
        f"/environments/{ENVIRONMENT_NAME}/versions/{ENVIRONMENT_VERSION}"
    )

    template = DeploymentTemplate(
        name=TEMPLATE_NAME,
        version=TEMPLATE_VERSION,
        description="Generic vLLM deployment template for single-GPU models on H100",
        environment=env_id,
        instance_type="Standard_NC40ads_H100_v5",
        instance_count=1,
        scoring_port=5001,
        scoring_path="/v1",
        model_mount_path="/opt/ml/model",
        environment_variables={
            "VLLM_MODEL_NAME": "/opt/ml/model",
            "VLLM_TENSOR_PARALLEL_SIZE": "1",
            "VLLM_MAX_MODEL_LEN": "131072",
            "VLLM_GPU_MEMORY_UTILIZATION": "0.9",
            "HF_HOME": "/tmp/hf_cache",
        },
    )

    result = ml_client.deployment_templates.create_or_update(template)
    print(f"[INFO] Deployment template created: {result.name} v{result.version}")
    print(f"       Instance type: Standard_NC40ads_H100_v5")
    print(f"       ID:            {result.id}")
    print("\n[RESULT]")
    print(json.dumps(result._to_dict(), indent=2, default=str))


if __name__ == "__main__":
    main()
