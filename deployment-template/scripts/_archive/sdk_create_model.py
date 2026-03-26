"""Create model in registry with defaultDeploymentTemplate via SDK."""
from azure.ai.ml import MLClient
from azure.identity import AzureCliCredential
from azure.ai.ml.entities import Model
from azure.ai.ml.entities._assets._artifacts.model import DefaultDeploymentTemplate

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
    version="4",
    type="custom_model",
    path="model-artifacts",
    description="Qwen3.5-0.8B with deployment template reference",
    default_deployment_template=ddt,
    tags={
        "source": "huggingface",
        "hf_model_id": "Qwen/Qwen3.5-0.8B",
    }
)

# Check REST serialization
rest_obj = model._to_rest_object()
print("REST type:", type(rest_obj).__name__)
print("Properties type:", type(rest_obj.properties).__name__)
if hasattr(rest_obj.properties, "default_deployment_template"):
    ddt_rest = rest_obj.properties.default_deployment_template
    print("DT in REST:", ddt_rest)
    if ddt_rest:
        print("DT asset_id:", ddt_rest.asset_id)
else:
    print("No DT in REST properties")

print("\nAttempting to create model in registry...")
try:
    result = ml_registry_client.models.create_or_update(model)
    print("SUCCESS!")
    print("Model name:", result.name)
    print("Model version:", result.version)
    if result.default_deployment_template:
        print("DT asset_id:", result.default_deployment_template.asset_id)
    else:
        print("DT: None (not returned)")
except Exception as e:
    print(f"FAILED: {type(e).__name__}: {e}")
