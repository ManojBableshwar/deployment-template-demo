"""Get SAS URL from registry for model upload, then use azcopy."""
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

# Monkey-patch to intercept the SAS URL
import azure.ai.ml._artifacts._artifact_utilities as au
original_fn = au._check_and_upload_path

sas_info = {}

def patched_check_and_upload(artifact, asset_type, datastore_name=None, sas_uri=None, **kwargs):
    """Intercept to capture SAS URI, then use azcopy instead of SDK upload."""
    print(f"INTERCEPTED: sas_uri={sas_uri[:100] if sas_uri else 'None'}...")
    if sas_uri:
        sas_info['sas_uri'] = sas_uri
    
    # Also capture blob_uri
    blob_uri = kwargs.get('blob_uri', None)
    if blob_uri:
        print(f"INTERCEPTED: blob_uri={blob_uri[:100]}...")
        sas_info['blob_uri'] = blob_uri
    
    print(f"INTERCEPTED: all kwargs keys = {list(kwargs.keys())}")
    
    # Now use azcopy with the SAS URI
    if sas_uri:
        source = str(artifact.path)
        dest = sas_uri
        if not dest.endswith('/'):
            # SAS URI might be container-level, append path
            dest = f"{dest}/model-artifacts"
        
        print(f"\nUsing azcopy to upload {source} to registry blob...")
        print(f"Dest: {dest[:100]}...")
        sys.stdout.flush()
        
        cmd = f'azcopy copy "{source}" "{dest}" --recursive --put-md5'
        ret = os.system(cmd)
        if ret != 0:
            print(f"azcopy failed with code {ret}")
            sys.exit(1)
        print("azcopy upload complete!")
        
        # Now return the blob URI so the model creation proceeds
        # We need to return what the original function returns
        from azure.ai.ml._artifacts._artifact_utilities import ArtifactUploadResult
        # Get the blob path
        container_url = sas_uri.split('?')[0]
        return container_url + "/model-artifacts", None
    
    # Fallback to original
    return original_fn(artifact, asset_type, datastore_name=datastore_name, sas_uri=sas_uri, **kwargs)

au._check_and_upload_path = patched_check_and_upload

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

print("Starting model create with azcopy upload...")
sys.stdout.flush()

try:
    result = ml_registry_client.models.create_or_update(model)
    print(f"\nSUCCESS! Model: {result.name} v{result.version}")
    if result.default_deployment_template:
        print(f"DT: {result.default_deployment_template.asset_id}")
except Exception as e:
    print(f"\nError: {type(e).__name__}: {e}")
    if sas_info:
        print(f"\nCaptured SAS info: {json.dumps({k: v[:100] for k,v in sas_info.items()})}")
