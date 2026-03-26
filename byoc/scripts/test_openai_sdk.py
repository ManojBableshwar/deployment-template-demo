"""OpenAI SDK inference test for BYOC deployment."""
import json
import os
import subprocess
import sys

def get_endpoint_info():
    scoring_uri = subprocess.run(
        ["az", "ml", "online-endpoint", "show",
         "--name", "qwen35-endpoint",
         "-w", "mabables-feb2026", "-g", "mabables-rg",
         "--query", "scoring_uri", "-o", "tsv"],
        capture_output=True, text=True
    ).stdout.strip()

    key = subprocess.run(
        ["az", "ml", "online-endpoint", "get-credentials",
         "--name", "qwen35-endpoint",
         "-w", "mabables-feb2026", "-g", "mabables-rg",
         "--query", "primaryKey", "-o", "tsv"],
        capture_output=True, text=True
    ).stdout.strip()

    return scoring_uri, key


def main():
    from openai import OpenAI

    scoring_uri, api_key = get_endpoint_info()
    base_url = scoring_uri.rstrip("/score").rstrip("/")

    print(f"Endpoint: {base_url}")
    print()

    client = OpenAI(base_url=f"{base_url}/v1", api_key=api_key)

    # Test 1: Non-streaming
    print("--- OpenAI SDK: chat.completions.create ---")
    response = client.chat.completions.create(
        model="Qwen3.5-0.8B",
        messages=[
            {"role": "user", "content": "Give me a short introduction to large language models."}
        ],
        max_tokens=256,
        temperature=0.7,
    )
    print(json.dumps(response.model_dump(), indent=2, default=str))

    # Test 2: Streaming
    print("\n--- OpenAI SDK: streaming ---")
    stream = client.chat.completions.create(
        model="Qwen3.5-0.8B",
        messages=[
            {"role": "user", "content": "Count from 1 to 5 briefly."}
        ],
        max_tokens=128,
        stream=True,
    )
    full_text = ""
    for chunk in stream:
        if chunk.choices and chunk.choices[0].delta.content:
            text = chunk.choices[0].delta.content
            full_text += text
            print(text, end="", flush=True)
    print(f"\n\n[Streamed text]: {full_text}")
    print("\n--- OpenAI SDK tests passed ---")


if __name__ == "__main__":
    main()
