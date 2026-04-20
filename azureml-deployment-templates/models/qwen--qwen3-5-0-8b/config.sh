#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# config.sh -- Version overrides for Qwen/Qwen3.5-0.8B
#
# Sourced by env.sh. Only set values that differ from auto-derived defaults.
# All resource names are derived from HF_MODEL_ID in env.sh.
# ------------------------------------------------------------------------------

# -- Version pins (override auto-derived defaults of "1") ----------------------
# Conditional: CLI flags (--version, --model-version, etc.) take priority.
# Note: ENVIRONMENT_VERSION is not pinned here because the vLLM environment is
# model-agnostic and shared across models. Override with --env-version if needed.
export MODEL_VERSION="${MODEL_VERSION:-50}"
export TEMPLATE_VERSION="${TEMPLATE_VERSION:-50}"
