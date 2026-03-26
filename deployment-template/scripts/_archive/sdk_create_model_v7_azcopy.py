"""Create model v7 in registry with DT - use SDK to get SAS, azcopy for upload."""
import subprocess
import json
import sys
import os

from azure.ai.ml import MLClient
from azure.identity import AzureCliCredential
from azure.ai.ml.entities import Model
from azure.ai.ml.entities._assets._artifacts.model import DefaultDeploymentTemplate

credential = AzureCliCredential()
ml_registry_client = MLClient(
    credential=credential,
    registry_name="mabables-reg-feb26"
)

# Step 1: Get the pre-signed upload URL from the registry 
# The SDK's _check_and_upload_path method handles this internally.
# Let's use the SDK's internal upload mechanism but with azcopy.

# First, let's see if we can get the blob SAS via the SDK's internal methods
ops = ml_registry_client.models
model_ops = ops

# Try to get a pending upload URL by starting the create process
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

# Use the _check_and_upload_path internal method to get the SAS URL
# then upload via azcopy ourselves
from azure.ai.ml._artifacts._artifact_utilities import _check_and_upload_path
from azure.ai.ml._scope_dependent_operations import OperationScope

print("Getting SAS upload URL from registry...")
sys.stdout.flush()

try:
    # The internal upload path for registry models
    # We need to call the datastore operations to get SAS
    ds_ops = ml_registry_client.datastores
    
    # Actually let's just monkey-patch the upload to use azcopy
    import azure.ai.ml._artifacts._artifact_utilities as artifact_utils
    original_upload = artifact_utils.upload_artifact
    
    def patched_upload(local_path, blob_client, *args, **kwargs):
        """Use azcopy instead of SDK upload for large files."""
        container_url = blob_client.url
        # Strip the blob name to get container URL
        container_base = container_url.rsplit("/", 1)[0] if "/" in container_url else container_url
        
        # Get the SAS from the URL
        print(f"\nUsing azcopy to upload to: {container_url[:100]}...")
        sys.stdout.flush()
        
        # Run azcopy with the full SAS URL
        dest = container_url
        cmd = ["azcopy", "copy", str(local_path), dest, "--recursive", "--put-md5"]
        print(f"Running: azcopy copy '{local_path}' '<dest>' --recursive --put-md5")
        sys.stdout.flush()
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
        if result.returncode != 0:
            print(f"azcopy stderr: {result.stderr}")
            raise RuntimeError(f"azcopy failed with code {result.returncode}")
        print(f"azcopy completed successfully")
        sys.stdout.flush()
    
    # Actually, the SDK upload flow is more complex than just upload_artifact.
    # Let me just run create_or_update which handles everything.
    # The issue is just speed. Let me try a different approach.
    
    print("Starting model upload (SDK handles SAS internally)...")
    sys.stdout.flush()
    result = ml_registry_client.models.create_or_update(model)
    print(f"\nSUCCESS! Model: {result.name} v{result.version}")
    print(f"Path: {result.path}")
    if result.default_deployment_template:
        print(f"DT asset_id: {result.default_deployment_template.asset_id}")
    else:
        print("DT: None")
except Exception as e:
    print(f"\nFAILED: {type(e).__name__}: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
