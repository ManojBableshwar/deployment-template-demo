"""Step 3: Register model in Azure ML registry.

NOTE: Model registration is SKIPPED in the SDK flow.

The Python SDK's built-in upload uses single-threaded blob uploads which fail with
BrokenPipeError / timeout on large model files (>1 GB). Model registration requires
azcopy for reliable large-file upload (chunked PutBlock, parallel, resilient to
connection resets).

Use the CLI script instead:
    bash scripts/cli/3-register-model.sh

The CLI script handles:
  1. startPendingUpload → SAS URI
  2. azcopy upload (~1.77 GB model artifacts)
  3. REST API model registration
  4. PATCH to associate deployment template
"""


def main():
    print("=" * 70)
    print("[SKIP] Step 3: Model registration requires azcopy (not available via SDK)")
    print()
    print("  The Python SDK's built-in upload fails for large model files (>1 GB)")
    print("  with BrokenPipeError. Use the CLI script instead:")
    print()
    print("    bash scripts/cli/3-register-model.sh")
    print()
    print("  The CLI script uses azcopy for reliable chunked uploads and registers")
    print("  the model via REST API with deployment template association.")
    print("=" * 70)

    # ── Original SDK model registration (commented out) ──────────────────
    #
    # import json
    # import os
    # from pathlib import Path
    #
    # from azure.ai.ml import MLClient
    # from azure.ai.ml.entities import Model
    # from azure.identity import DefaultAzureCredential
    # from huggingface_hub import snapshot_download
    #
    # SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "...")
    # RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "...")
    # AZUREML_REGISTRY = os.environ.get("AZUREML_REGISTRY", "...")
    # MODEL_NAME = os.environ.get("MODEL_NAME", "Qwen35-08B")
    # MODEL_VERSION = os.environ.get("MODEL_VERSION", "40")
    # HF_MODEL_ID = os.environ.get("HF_MODEL_ID", "Qwen/Qwen3.5-0.8B")
    # TEMPLATE_NAME = os.environ.get("TEMPLATE_NAME", "vllm-1gpu-h100")
    # TEMPLATE_VERSION = os.environ.get("TEMPLATE_VERSION", "40")
    #
    # MODEL_DIR = Path(__file__).resolve().parent.parent.parent.parent / "model-artifacts"
    #
    # # Download model from HuggingFace
    # snapshot_download(HF_MODEL_ID, local_dir=str(MODEL_DIR))
    #
    # # Register model — FAILS for large files (>1 GB) with BrokenPipeError.
    # # Use azcopy + REST API (CLI script) instead.
    # credential = DefaultAzureCredential()
    # ml_client = MLClient(
    #     credential=credential,
    #     subscription_id=SUBSCRIPTION_ID,
    #     resource_group_name=RESOURCE_GROUP,
    #     registry_name=AZUREML_REGISTRY,
    # )
    # template_asset_id = (
    #     f"azureml://registries/{AZUREML_REGISTRY}"
    #     f"/deploymentTemplates/{TEMPLATE_NAME}/versions/{TEMPLATE_VERSION}"
    # )
    # model = Model(
    #     name=MODEL_NAME,
    #     version=MODEL_VERSION,
    #     path=str(MODEL_DIR),
    #     type="custom_model",
    #     description="Qwen3.5-0.8B with deployment template",
    #     tags={
    #         "source": "huggingface",
    #         "hf_model_id": HF_MODEL_ID,
    #         "parameters": "0.8B",
    #         "framework": "transformers",
    #     },
    #     properties={
    #         "defaultDeploymentTemplate": template_asset_id,
    #     },
    # )
    # result = ml_client.models.create_or_update(model)
    # print(json.dumps(result._to_dict(), indent=2, default=str))


if __name__ == "__main__":
    main()
