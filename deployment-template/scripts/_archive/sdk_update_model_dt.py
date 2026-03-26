"""Update model v5 in registry to add defaultDeploymentTemplate via SDK."""
from azure.ai.ml import MLClient
from azure.identity import AzureCliCredential
from azure.ai.ml.entities import Model
from azure.ai.ml.entities._assets._artifacts.model import DefaultDeploymentTemplate

credential = AzureCliCredential()
ml_registry_client = MLClient(
    credential=credential,
    registry_name="mabables-reg-feb26"
)

# Get existing model v5 from registry
print("Getting model v5...")
model = ml_registry_client.models.get(name="Qwen35-08B", version="5")
print(f"Model: {model.name} v{model.version}")
print(f"Path: {model.path}")
print(f"Current DT: {model.default_deployment_template}")

# Set the DT
model.default_deployment_template = DefaultDeploymentTemplate(
    asset_id="azureml://registries/mabables-reg-feb26/deploymentTemplates/vllm-1gpu-h100/versions/3"
)
print(f"New DT: {model.default_deployment_template.asset_id}")

# Update
print("Updating model...")
try:
    result = ml_registry_client.models.create_or_update(model)
    print(f"SUCCESS! DT: {result.default_deployment_template}")
    if result.default_deployment_template:
        print(f"DT asset_id: {result.default_deployment_template.asset_id}")
except Exception as e:
    print(f"FAILED: {type(e).__name__}: {e}")
