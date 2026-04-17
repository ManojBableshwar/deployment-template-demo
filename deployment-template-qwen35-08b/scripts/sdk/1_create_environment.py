"""Step 1: Create vLLM environment in workspace (Dockerfile build), share to registry.

Mirrors the CLI script (cli/1-create-environment.sh):
  1. Create environment in workspace using Dockerfile build context.
  2. Poll the Studio image API until the Docker image is built.
  3. Share the built environment from workspace to registry.

Note: environment sharing uses subprocess (az ml environment share) because
the Python SDK does not expose an environment share method.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import requests
from azure.ai.ml import MLClient
from azure.ai.ml.entities import BuildContext, Environment
from azure.identity import DefaultAzureCredential

SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "75703df0-38f9-4e2e-8328-45f6fc810286")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "mabables-rg")
AZUREML_WORKSPACE = os.environ.get("AZUREML_WORKSPACE", "mabables-feb2026")
WORKSPACE_LOCATION = os.environ.get("WORKSPACE_LOCATION", "eastus2")
AZUREML_REGISTRY = os.environ.get("AZUREML_REGISTRY", "mabables-reg-feb26")
ENVIRONMENT_NAME = os.environ.get("ENVIRONMENT_NAME", "vllm-qwen35")
ENVIRONMENT_VERSION = os.environ.get("ENVIRONMENT_VERSION", "40")

SCRIPT_DIR = Path(__file__).resolve().parent
BUILD_CONTEXT_DIR = str(SCRIPT_DIR / ".." / "cli" / "yaml")


def main():
    credential = DefaultAzureCredential()

    ws_client = MLClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        resource_group_name=RESOURCE_GROUP,
        workspace_name=AZUREML_WORKSPACE,
    )
    reg_client = MLClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        resource_group_name=RESOURCE_GROUP,
        registry_name=AZUREML_REGISTRY,
    )

    # ── Create environment in workspace (Dockerfile build) ───────────────
    try:
        ws_client.environments.get(ENVIRONMENT_NAME, ENVIRONMENT_VERSION)
        print(f"[INFO] Environment '{ENVIRONMENT_NAME}' v{ENVIRONMENT_VERSION} already exists in workspace — proceeding.")
    except Exception:
        print(f"[INFO] Creating environment '{ENVIRONMENT_NAME}' v{ENVIRONMENT_VERSION} in workspace '{AZUREML_WORKSPACE}'…")
        env = Environment(
            name=ENVIRONMENT_NAME,
            version=ENVIRONMENT_VERSION,
            build=BuildContext(path=BUILD_CONTEXT_DIR, dockerfile_path="Dockerfile"),
            description="vLLM OpenAI-compatible inference server with runit for Azure ML managed endpoints",
            tags={"framework": "vllm", "model_family": "qwen3.5"},
        )
        result = ws_client.environments.create_or_update(env)
        print(f"[INFO] Environment create completed: {result.name} v{result.version}")

    # ── Share to registry ────────────────────────────────────────────────
    try:
        reg_client.environments.get(ENVIRONMENT_NAME, ENVIRONMENT_VERSION)
        print(f"[INFO] Environment '{ENVIRONMENT_NAME}' v{ENVIRONMENT_VERSION} already exists in registry — skipping promotion.")
    except Exception:
        # Poll the environment image API for build completion
        print("[INFO] Waiting for environment image build to complete (polling every 30s, up to 1 hour)…")
        env_image_api = (
            f"https://ml.azure.com/api/{WORKSPACE_LOCATION}/environment/v1.0"
            f"/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}"
            f"/providers/Microsoft.MachineLearningServices/workspaces/{AZUREML_WORKSPACE}"
            f"/environments/{ENVIRONMENT_NAME}/versions/{ENVIRONMENT_VERSION}"
            f"/image?secrets=false"
        )
        max_wait, interval, elapsed = 3600, 30, 0
        while elapsed < max_wait:
            token = credential.get_token("https://management.azure.com/.default").token
            try:
                resp = requests.get(
                    env_image_api,
                    headers={"Authorization": f"Bearer {token}"},
                    timeout=30,
                )
                if resp.ok:
                    image_exists = resp.json().get("imageExistsInRegistry", "")
                    if str(image_exists).lower() == "true":
                        print(f"[INFO] Environment image build completed ({elapsed}s elapsed).")
                        break
            except requests.RequestException:
                pass
            print(f"[INFO] Image not ready yet ({elapsed}s elapsed) — waiting {interval}s…")
            time.sleep(interval)
            elapsed += interval
        else:
            print(f"[ERROR] Timed out waiting for environment image build after {max_wait}s")
            sys.exit(1)

        # Share from workspace to registry (SDK doesn't have a share method)
        print(f"[INFO] Promoting environment from workspace to registry '{AZUREML_REGISTRY}'…")
        subprocess.run(
            [
                "az", "ml", "environment", "share",
                "--name", ENVIRONMENT_NAME,
                "--version", ENVIRONMENT_VERSION,
                "--workspace-name", AZUREML_WORKSPACE,
                "--resource-group", RESOURCE_GROUP,
                "--share-with-name", ENVIRONMENT_NAME,
                "--share-with-version", ENVIRONMENT_VERSION,
                "--registry-name", AZUREML_REGISTRY,
            ],
            check=True,
        )
        print("[INFO] Environment share command completed — verifying…")

        # Verify
        try:
            reg_client.environments.get(ENVIRONMENT_NAME, ENVIRONMENT_VERSION)
            print("[INFO] Confirmed: environment exists in registry.")
        except Exception:
            print("[ERROR] Environment share succeeded but environment not found in registry!")
            sys.exit(1)

    # ── Show registry environment ────────────────────────────────────────
    env = reg_client.environments.get(ENVIRONMENT_NAME, ENVIRONMENT_VERSION)
    print("\n[INFO] Showing registry environment:")
    print(json.dumps(env._to_dict(), indent=2, default=str))


if __name__ == "__main__":
    main()
