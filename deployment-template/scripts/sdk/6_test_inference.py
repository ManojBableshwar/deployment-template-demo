"""Step 6: Test the online deployment with OpenAI SDK chat completion."""

import json
import os

from azure.ai.ml import MLClient
from azure.identity import DefaultAzureCredential
from openai import OpenAI

SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "75703df0-38f9-4e2e-8328-45f6fc810286")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "mabables-rg")
WORKSPACE_NAME = os.environ.get("AZUREML_WORKSPACE", "mabables-feb2026")
ENDPOINT_NAME = os.environ.get("ENDPOINT_NAME", "qwen35-endpoint")


def main():
    credential = DefaultAzureCredential()
    ml_client = MLClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        resource_group_name=RESOURCE_GROUP,
        workspace_name=WORKSPACE_NAME,
    )

    # Get endpoint details
    endpoint = ml_client.online_endpoints.get(ENDPOINT_NAME)
    keys = ml_client.online_endpoints.get_keys(ENDPOINT_NAME)

    scoring_uri = endpoint.scoring_uri
    base_url = scoring_uri.rstrip("/score").rstrip("/")

    print(f"[INFO] Endpoint: {ENDPOINT_NAME}")
    print(f"[INFO] Scoring URI: {scoring_uri}")

    # Create OpenAI client pointing to the Azure ML endpoint
    client = OpenAI(
        base_url=f"{base_url}/v1",
        api_key=keys.primary_key,
    )

    # --- Test 1: Simple text completion ---
    print("\n[TEST 1] Simple text completion:")
    response = client.chat.completions.create(
        model="Qwen3.5-0.8B",
        messages=[
            {"role": "user", "content": "Give me a short introduction to large language models."}
        ],
        max_tokens=512,
        temperature=1.0,
        top_p=1.0,
    )
    print(json.dumps(response.model_dump(), indent=2, default=str))

    # --- Test 2: Multi-turn conversation ---
    print("\n[TEST 2] Multi-turn conversation:")
    response = client.chat.completions.create(
        model="Qwen3.5-0.8B",
        messages=[
            {"role": "system", "content": "You are a helpful AI assistant."},
            {"role": "user", "content": "What is vLLM?"},
            {"role": "assistant", "content": "vLLM is an open-source library for fast LLM inference and serving."},
            {"role": "user", "content": "How does it achieve high throughput?"},
        ],
        max_tokens=512,
        temperature=1.0,
        top_p=1.0,
    )
    print(json.dumps(response.model_dump(), indent=2, default=str))

    # --- Test 3: Streaming ---
    print("\n[TEST 3] Streaming response:")
    stream = client.chat.completions.create(
        model="Qwen3.5-0.8B",
        messages=[
            {"role": "user", "content": "Count from 1 to 10 and explain each number briefly."}
        ],
        max_tokens=512,
        temperature=1.0,
        top_p=1.0,
        stream=True,
    )
    for chunk in stream:
        if chunk.choices and chunk.choices[0].delta.content:
            print(chunk.choices[0].delta.content, end="", flush=True)
    print()

    print("\n[INFO] All tests complete.")


if __name__ == "__main__":
    main()
