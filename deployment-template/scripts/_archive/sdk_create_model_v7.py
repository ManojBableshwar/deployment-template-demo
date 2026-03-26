"""Create model v7 in registry with DT using SDK internals - handles upload via SAS from service."""
from azure.ai.ml import MLClient
from azure.identity import AzureCliCredential
from azure.ai.ml.entities import Model
from azure.ai.ml.entities._assets._artifacts.model import DefaultDeploymentTemplate
import sys

credential = AzureCliCredential()
ml_registry_client = MLClient(
    credential=credential,
    registry_name="mabables-reg-feb26"
)

ddt = DefaultDeploymentTemplate(
    asset_id="azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/3"
)

model = Model(
    name="Qwen35-08B",
    version="7",
    type="custom_model",
    path="model-artifacts",
    description="Qwen3.5-0.8B with deployment template (full artifacts)",
    default_deployment_template=ddt,
    tags={
        "source": "huggingface",
        "hf_model_id": "Qwen/Qwen3.5-0.8B",
        "parameters": "0.8B",
        "framework": "transformers",
        "architecture": "qwen3_5",
    }
)

print("Creating model with DT in registry (uploading 1.77GB)...")
print(f"DT: {model.default_deployment_template.asset_id}")
sys.stdout.flush()

try:
    result = ml_registry_client.models.create_or_update(model)
    print(f"\nSUCCESS! Model: {result.name} v{result.version}")
    print(f"Path: {result.path}")
    if result.default_deployment_template:
        print(f"DT asset_id: {result.default_deployment_template.asset_id}")
    else:
        print("DT: None (not returned)")
except Exception as e:
    print(f"\nFAILED: {type(e).__name__}: {e}")
    sys.exit(1)
