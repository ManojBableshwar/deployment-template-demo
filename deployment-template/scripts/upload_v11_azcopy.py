"""
Upload model v11 to registry using azcopy for reliable large file upload.
Monkey-patches the SDK's blob upload_directory to use azcopy, then runs
az ml model create via CLI internals (the only path that persists DT).

Must be run with the az CLI's Python interpreter:
  /opt/homebrew/Cellar/azure-cli/2.83.0/libexec/bin/python scripts/upload_v11_azcopy.py
"""
import subprocess
import sys
import os
from pathlib import Path

# Add the ML extension to the path
sys.path.insert(0, os.path.expanduser("~/.azure/cliextensions/ml"))

# Monkey-patch BEFORE the CLI loads the module
import azure.ai.ml._artifacts._blob_storage_helper as blob_helper
from azure.ai.ml._utils._asset_utils import get_upload_files_from_folder

def _azcopy_upload_directory(storage_client, source, dest, msg, show_progress, ignore_file):
    """Replace Python blob upload with azcopy."""
    source_path = Path(source).resolve()
    prefix = "" if dest == "" else dest + "/"
    prefix += os.path.basename(source_path) + "/"

    # Enumerate files for indicator_file and counts
    upload_paths = get_upload_files_from_folder(source_path, prefix=prefix, ignore_file=ignore_file)
    upload_paths = sorted(upload_paths)
    if len(upload_paths) == 0:
        raise Exception(f"Empty directory: {source}")
    storage_client.total_file_count = len(upload_paths)
    storage_client.indicator_file = upload_paths[0][1]

    # Build the destination URL for azcopy
    container_url = storage_client.container_client.url
    if dest:
        azcopy_dest = f"{container_url}/{dest}"
    else:
        azcopy_dest = container_url

    print(f"\n>>> Using azcopy for upload ({len(upload_paths)} files)...", flush=True)
    print(f">>> Source: {source_path}", flush=True)
    print(f">>> Container: {storage_client.container}", flush=True)

    result = subprocess.run(
        ["azcopy", "copy", str(source_path), azcopy_dest, "--recursive", "--put-md5"],
    )
    if result.returncode != 0:
        raise RuntimeError(f"azcopy upload failed with return code {result.returncode}")

    # Mark all files as uploaded
    storage_client.uploaded_file_count = storage_client.total_file_count
    print(f">>> azcopy upload complete! ({storage_client.total_file_count} files)", flush=True)

# Apply the monkey-patch
blob_helper.upload_directory = _azcopy_upload_directory

# Now run the CLI
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
MODEL_YAML = os.environ.get("MODEL_YAML", str(REPO_ROOT / "deployment-template" / "scripts" / "cli" / "yaml" / "model.yml"))
print(f"Running az ml model create with azcopy-patched upload ({MODEL_YAML})...", flush=True)
sys.argv = [
    "az", "ml", "model", "create",
    "--file", MODEL_YAML,
    "--registry-name", "mabables-reg-feb26",
]

os.environ["AZ_INSTALLER"] = "HOMEBREW"
from azure.cli.core import get_default_cli
cli = get_default_cli()
exit_code = cli.invoke(sys.argv[1:])

if exit_code == 0:
    print("\nModel v11 created successfully!", flush=True)
else:
    print(f"\nModel creation failed with exit code {exit_code}", flush=True)
    sys.exit(exit_code)
