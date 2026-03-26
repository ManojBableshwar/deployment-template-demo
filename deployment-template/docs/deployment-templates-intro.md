# Azure ML Deployment Templates

> **Status**: Preview (under active development)  
> **Probed on**: March 24, 2026 — Azure ML CLI extension v2, Python SDK `azure-ai-ml` v1.32.0

## Overview

Deployment templates are **reusable, versioned configurations** that define how models should be deployed to Azure ML endpoints. They are stored in **Azure ML registries** (not workspaces), enabling standardized deployment patterns to be shared across teams and projects.

## CLI Support (`az ml deployment-template`)

The Azure ML CLI v2 exposes a full `deployment-template` subgroup with six commands:

| Command | Description |
|---------|-------------|
| `create` | Create a new deployment template from a YAML file |
| `show` | Get a specific template by name and version |
| `list` | List all templates in a registry |
| `update` | Update metadata (description, tags) of an existing template |
| `archive` | Mark a template as inactive (hidden from list by default) |
| `restore` | Restore a previously archived template |

### Key Details

- **Registry-scoped only** — all commands require `--registry-name`; workspace-based operations are not supported.
- **YAML-driven creation** — `create` accepts a `--file` parameter pointing to a YAML spec. The reference schema is at `https://aka.ms/ml-cli-v2-deployment-template-yaml`.
- **Metadata updates** — `update` only modifies `description` and `tags`. For structural changes (endpoints, deployment config), use `create` with a new YAML file.
- **Async support** — `create`, `archive`, and `restore` support `--no-wait`.

### CLI Examples

```bash
# Create from YAML
az ml deployment-template create --file template.yml --registry-name myregistry

# Create with name/version overrides
az ml deployment-template create --file template.yml --name custom-template --version 2 --registry-name myregistry

# List all templates
az ml deployment-template list --registry-name myregistry --output table

# Show a specific version
az ml deployment-template show --name my-template --version 1 --registry-name myregistry

# Update description and tags
az ml deployment-template update --name my-template --version 1 --registry-name myregistry \
  --set "description=Production template" --set "tags=status=active"

# Archive / restore
az ml deployment-template archive --name my-template --version 1 --registry-name myregistry
az ml deployment-template restore --name my-template --version 1 --registry-name myregistry
```

## Python SDK Support (`azure-ai-ml` v1.32.0)

### Entity Classes

| Class | Module | Purpose |
|-------|--------|---------|
| `DeploymentTemplate` | `azure.ai.ml.entities` | Full deployment template definition |
| `DefaultDeploymentTemplate` | `azure.ai.ml.entities` | Lightweight reference by asset ID |

#### `DeploymentTemplate.__init__` Parameters

```
name, version, description, environment, request_settings,
liveness_probe, readiness_probe, instance_count, instance_type,
model, code_configuration, environment_variables, app_insights_enabled,
allowed_instance_types, default_instance_type, scoring_port,
scoring_path, model_mount_path, type, deployment_template_type, stage
```

### Operations via `MLClient.deployment_templates`

| Method | Description |
|--------|-------------|
| `create_or_update(deployment_template)` | Create or update a template |
| `get(name, version)` | Retrieve a specific template |
| `list(name, tags, count, stage, list_view_type)` | List templates (default: active only) |
| `archive(name, version)` | Archive a template |
| `restore(name, version)` | Restore an archived template |
| `delete(name, version)` | Permanently delete a template |

### YAML Loading

```python
from azure.ai.ml import load_deployment_template

template = load_deployment_template(source="template.yml")
```

### SDK Example

```python
from azure.ai.ml import MLClient, load_deployment_template
from azure.identity import DefaultAzureCredential

# Connect to a registry (not a workspace)
ml_client = MLClient(
    credential=DefaultAzureCredential(),
    registry_name="myregistry",
)

# Load and create
template = load_deployment_template(source="template.yml")
ml_client.deployment_templates.create_or_update(template)

# List all active templates
for t in ml_client.deployment_templates.list():
    print(t.name, t.version)
```

## Key Takeaways

1. **Preview feature** — both CLI and SDK surfaces are marked as preview/under development.
2. **Registry-only** — deployment templates live in registries, not workspaces, reinforcing their role as shared organizational assets.
3. **Full CRUD + lifecycle** — create, read, update, delete, archive, and restore are all supported.
4. **SDK has `delete`** — the Python SDK exposes a `delete` method not present in the CLI.
5. **Parity** — CLI and SDK are largely symmetric, with the SDK offering slightly more flexibility (e.g., `create_or_update` semantics, `delete`).
