"""Get SAS URL from registry for model upload, then use azcopy."""
import subprocess
import json
import sys
import os
import requests

from azure.ai.ml import MLClient
from azure.identity import AzureCliCredential
from azure.ai.ml.entities import Model
from azure.ai.ml.entities._assets._artifacts.model import DefaultDeploymentTemplate

credential = AzureCliCredential()
ml_registry_client = MLClient(
    credential=credential,
    registry_name="mabables-reg-feb26"
)

# Access internal operations to get the SAS for the pending upload
ops = ml_registry_client.models
service_client = ops._service_client

# Get data reference for pending upload  
print("Getting pending upload URL from registry...")
try:
    # The registry model create flow:
    # 1. begin_create_or_update -> returns 202
    # 2. The 202 response includes Location header with the operation URL
    # 3. The SDK polls until complete
    # The blob SAS comes from a different call - get_sas_credential
    
    # Let's look at how _check_and_upload_path works for registry
    import azure.ai.ml._artifacts._artifact_utilities as au
    import inspect
    
    # Find _check_and_upload_path
    src = inspect.getsource(au._check_and_upload_path)
    # Find where it gets the SAS for registry
    for i, line in enumerate(src.split('\n')):
        if 'sas' in line.lower() or 'credential' in line.lower() or 'temporary' in line.lower() or 'blob' in line.lower():
            print(f"  Line {i}: {line.strip()}")
    
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()

# Alternative: Get the SAS URL by intercepting the SDK's upload
print("\n\nIntercepting upload to get SAS URL...")

# Monkey-patch the blob upload to extract the SAS URL
import azure.ai.ml._artifacts._blob_storage_helper as bsh

original_upload = None
sas_url_captured = [None]

if hasattr(bsh, 'BlobStorageClient'):
    # Patch the upload_file method
    cls = bsh.BlobStorageClient
    if hasattr(cls, 'upload'):
        original_upload = cls.upload
        def patched_upload(self, *args, **kwargs):
            # Extract the account URL + SAS
            if hasattr(self, 'account_url'):
                print(f"Account URL: {self.account_url}")
            if hasattr(self, 'container'):
                print(f"Container: {self.container}")
            if hasattr(self, 'credential'):
                print(f"Credential type: {type(self.credential).__name__}")
                if hasattr(self.credential, 'signature'):
                    sas_url_captured[0] = f"{self.account_url}?{self.credential.signature}"
                    print(f"SAS URL captured!")
            # Don't actually upload, just get the URL
            raise InterruptedError("Upload intercepted - SAS URL captured")
        cls.upload = patched_upload

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

try:
    result = ml_registry_client.models.create_or_update(model)
    print(f"Model created: {result.name} v{result.version}")
except InterruptedError:
    print("Upload intercepted successfully!")
    if sas_url_captured[0]:
        print(f"SAS URL: {sas_url_captured[0][:100]}...")
except Exception as e:
    print(f"Error during create: {type(e).__name__}: {e}")
