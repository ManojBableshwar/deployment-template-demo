"""Step 2: Create deployment template in the Azure ML registry.

Uses az CLI with the validated YAML (scripts/cli/yaml/deployment-template.yml)
because the SDK DeploymentTemplate entity does not reliably support all fields
(probes, allowed_instance_types, deployment_template_type).
"""

import os
import subprocess
from pathlib import Path

SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "75703df0-38f9-4e2e-8328-45f6fc810286")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "mabables-rg")
AZUREML_REGISTRY = os.environ.get("AZUREML_REGISTRY", "mabables-reg-feb26")
TEMPLATE_NAME = os.environ.get("TEMPLATE_NAME", "vllm-1gpu-h100")
TEMPLATE_VERSION = os.environ.get("TEMPLATE_VERSION", "40")

SCRIPT_DIR = Path(__file__).resolve().parent
DT_YAML = str(SCRIPT_DIR / ".." / "cli" / "yaml" / "deployment-template.yml")


def main():
    subprocess.run(
        ["az", "account", "set", "--subscription", SUBSCRIPTION_ID],
        check=True,
    )

    # Check if deployment template already exists
    result = subprocess.run(
        [
            "az", "ml", "deployment-template", "show",
            "--name", TEMPLATE_NAME,
            "--version", TEMPLATE_VERSION,
            "--registry-name", AZUREML_REGISTRY,
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode == 0:
        print(f"[INFO] Deployment template '{TEMPLATE_NAME}' v{TEMPLATE_VERSION} already exists — skipping creation.")
    else:
        print(f"[INFO] Creating deployment template '{TEMPLATE_NAME}' v{TEMPLATE_VERSION} in registry '{AZUREML_REGISTRY}'…")
        subprocess.run(
            [
                "az", "ml", "deployment-template", "create",
                "--file", DT_YAML,
                "--registry-name", AZUREML_REGISTRY,
            ],
            check=True,
        )
        print("[INFO] Deployment template created.")

    # Show details
    print("\n[INFO] Showing details:")
    subprocess.run(
        [
            "az", "ml", "deployment-template", "show",
            "--name", TEMPLATE_NAME,
            "--version", TEMPLATE_VERSION,
            "--registry-name", AZUREML_REGISTRY,
            "-o", "json",
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
