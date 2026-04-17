# Bug: `allowed_instance_types` rejects YAML list, requires space-delimited string

## Summary

The `allowed_instance_types` field in deployment template YAML is documented and
expected to accept a list of strings, but the CLI schema (`DeploymentTemplateSchema`)
uses `fields.Str()` instead of `fields.List(fields.Str())`. Passing a YAML list
causes a validation error. The workaround is a space-delimited string.

## Steps to reproduce

1. Create a deployment template YAML with `allowed_instance_types` as a list:

```yaml
allowed_instance_types:
  - Standard_NC24ads_A100_v4
  - Standard_NC40ads_H100_v5
```

2. Run:

```bash
az ml deployment-template create --file deployment-template.yml --registry-name <registry>
```

## Error output

```
Traceback (most recent call last):
  ...
marshmallow.exceptions.ValidationError: {'allowed_instance_types': ['Not a valid string.']}
```

The CLI deserializes the YAML list into a Python list, but the marshmallow schema
field `allowed_instance_types = fields.Str()` expects a single string, so
validation fails.

## Root cause

In the Azure ML CLI extension (`azure-ai-ml`), the `DeploymentTemplateSchema`
defines `allowed_instance_types` as `fields.Str()` rather than
`fields.List(fields.Str())`. This means only a single string value is accepted.

## Workaround

Use a space-delimited string instead of a YAML list:

```yaml
# Works (space-delimited string)
allowed_instance_types: "Standard_NC24ads_A100_v4 Standard_NC40ads_H100_v5"

# Fails (YAML list)
allowed_instance_types:
  - Standard_NC24ads_A100_v4
  - Standard_NC40ads_H100_v5
```

## Fix status

- **Feature 5150043** was merged to change the field to `fields.List(fields.Str())`,
  but has **not yet been released** as of 2026-04-16.
- Current CLI version tested: `azure-cli 2.83.0`, `ml extension 2.42.0`.

## Impact

- Users following standard YAML conventions will hit this error on every DT creation.
- The space-delimited workaround is unintuitive and undocumented.
- Once the fix ships, both formats should work (the REST API already accepts a list).
