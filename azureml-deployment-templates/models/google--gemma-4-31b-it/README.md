# google/gemma-4-31B-it

> Auto-generated status page — updated by E2E pipeline runs.
> Last updated: 2026-04-20 08:56:36

## Latest Run

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-20_07-23-16` |
| **Status** | **FAILED** |
| **Versions** | model=6  env=6  dt=6 |
| **SKUs** | h100 a100 |
| **Total time** | 93m 19s |
| **Steps** | 7/8 passed |
| **Failed** | 7-benchmark |

### Command

```bash
azureml-deployment-templates/scripts/run-e2e-cli.sh --hf-model google/gemma-4-31B-it --version 6 --tp 2 --sku Standard_NC80adis_H100_v5 --sku Standard_NC48ads_A100_v4
```

### Step Results

```
  STEP                                      TIME  STATUS    ACTION
  0-validate-model                          0m 00s  [PASS]    CREATED
  1-create-environment                      0m 30s  [PASS]    CREATED
  2-create-deployment-template              0m 08s  [PASS]    CREATED
  3-register-model                          0m 07s  [PASS]    CREATED
  4-create-online-endpoint                  0m 09s  [PASS]    CREATED
    └─ a100                                 0m 03s            CREATED
    └─ h100                                 0m 03s            CREATED
  5-create-online-deployment                0m 10s  [PASS]    CREATED
    └─ a100                                 0m 03s            CREATED
    └─ h100                                 0m 02s            CREATED
  6-test-inference                          1m 03s  [PASS]    CREATED
    └─ debug                                0m 15s            CREATED
    └─ a100                                 0m 36s            CREATED
    └─ debug                                0m 12s            CREATED
    └─ h100                                 0m 27s            CREATED
  7-benchmark                              91m 12s  [FAIL]  
    └─ a100                                90m 43s            CREATED
    └─ h100                                85m 25s            CREATED
```

## Inference API Tests

#### H100 — llm-api-spec results

Passed: 21 | Failed: 1 | Unsupported: 2 | N/A: 6 | Total: 30

| # | Capability | Result | Details |
|---|-----------|--------|---------|
| 1 | [text_input](#google--gemma-4-31b-it-h100-text-input) | ✅ passed | Text input accepted and processed |
| 2 | [text_output](#google--gemma-4-31b-it-h100-text-output) | ✅ passed | Response contains text content |
| 3 | [json_output](#google--gemma-4-31b-it-h100-json-output) | ✅ passed | Response is valid JSON |
| 4 | [structured_output](#google--gemma-4-31b-it-h100-structured-output) | ✅ passed | Output conforms to JSON schema |
| 5 | [tool_calling](#google--gemma-4-31b-it-h100-tool-calling) | ✅ passed | Tool call returned: get_weather |
| 6 | [tool_choice_auto](#google--gemma-4-31b-it-h100-tool-choice-auto) | ✅ passed | tool_choice='auto' accepted |
| 7 | [tool_choice_none](#google--gemma-4-31b-it-h100-tool-choice-none) | ✅ passed | tool_choice='none' correctly suppressed tool calls |
| 8 | [tool_choice_required](#google--gemma-4-31b-it-h100-tool-choice-required) | ✅ passed | tool_choice='required' forced a tool call |
| 9 | [tool_choice_function](#google--gemma-4-31b-it-h100-tool-choice-function) | ✅ passed | tool_choice forced specific function 'get_weather' |
| 10 | [multiple_tool_calls](#google--gemma-4-31b-it-h100-multiple-tool-calls) | ✅ passed | Multiple tool calls returned: 2 |
| 11 | [parallel_tool_calls](#google--gemma-4-31b-it-h100-parallel-tool-calls) | ✅ passed | parallel_tool_calls parameter accepted |
| 12 | [image_input_url](#google--gemma-4-31b-it-h100-image-input-url) | ⚠️ unsupported | Image URL input failed: Client error '424 Failed Dependency' for url 'https://go |
| 13 | [image_input_base64](#google--gemma-4-31b-it-h100-image-input-base64) | ✅ passed | Base64 image accepted and processed |
| 14 | [image_input_multi](#google--gemma-4-31b-it-h100-image-input-multi) | ✅ passed | Multiple images accepted and processed |
| 15 | [image_output](#google--gemma-4-31b-it-h100-image-output) | ❌ failed | No image content in response |
| 16 | [file_input_inline](#google--gemma-4-31b-it-h100-file-input-inline) | ➖ not applicable | Not applicable for this schema |
| 17 | [file_input_reference](#google--gemma-4-31b-it-h100-file-input-reference) | ➖ not applicable | Not applicable for this schema |
| 18 | [built_in_tools](#google--gemma-4-31b-it-h100-built-in-tools) | ➖ not applicable | Not applicable for this schema |
| 19 | [streaming](#google--gemma-4-31b-it-h100-streaming) | ✅ passed | Streaming produced 15 chunks |
| 20 | [stop_sequences](#google--gemma-4-31b-it-h100-stop-sequences) | ✅ passed | Stop sequence was respected |
| 21 | [logprobs](#google--gemma-4-31b-it-h100-logprobs) | ✅ passed | Logprobs returned with token data |
| 22 | [seeded_determinism](#google--gemma-4-31b-it-h100-seeded-determinism) | ✅ passed | Deterministic output with seed=42: '4' |
| 23 | [long_prompt_acceptance](#google--gemma-4-31b-it-h100-long-prompt-acceptance) | ✅ passed | Long prompt (22574 chars) accepted |
| 24 | [previous_response_id](#google--gemma-4-31b-it-h100-previous-response-id) | ➖ not applicable | Not applicable for this schema |
| 25 | [background_mode](#google--gemma-4-31b-it-h100-background-mode) | ➖ not applicable | Not applicable for this schema |
| 26 | [response_retrieval](#google--gemma-4-31b-it-h100-response-retrieval) | ➖ not applicable | Not applicable for this schema |
| 27 | [normalization](#google--gemma-4-31b-it-h100-normalization) | ✅ passed | Response successfully normalized |
| 28 | [regex_constraints](#google--gemma-4-31b-it-h100-regex-constraints) | ✅ passed | Output matches regex: 482-19-6307 |

#### A100 — llm-api-spec results

Passed: 21 | Failed: 1 | Unsupported: 2 | N/A: 6 | Total: 30

| # | Capability | Result | Details |
|---|-----------|--------|---------|
| 1 | [text_input](#google--gemma-4-31b-it-a100-text-input) | ✅ passed | Text input accepted and processed |
| 2 | [text_output](#google--gemma-4-31b-it-a100-text-output) | ✅ passed | Response contains text content |
| 3 | [json_output](#google--gemma-4-31b-it-a100-json-output) | ✅ passed | Response is valid JSON |
| 4 | [structured_output](#google--gemma-4-31b-it-a100-structured-output) | ✅ passed | Output conforms to JSON schema |
| 5 | [tool_calling](#google--gemma-4-31b-it-a100-tool-calling) | ✅ passed | Tool call returned: get_weather |
| 6 | [tool_choice_auto](#google--gemma-4-31b-it-a100-tool-choice-auto) | ✅ passed | tool_choice='auto' accepted |
| 7 | [tool_choice_none](#google--gemma-4-31b-it-a100-tool-choice-none) | ✅ passed | tool_choice='none' correctly suppressed tool calls |
| 8 | [tool_choice_required](#google--gemma-4-31b-it-a100-tool-choice-required) | ✅ passed | tool_choice='required' forced a tool call |
| 9 | [tool_choice_function](#google--gemma-4-31b-it-a100-tool-choice-function) | ✅ passed | tool_choice forced specific function 'get_weather' |
| 10 | [multiple_tool_calls](#google--gemma-4-31b-it-a100-multiple-tool-calls) | ✅ passed | Multiple tool calls returned: 2 |
| 11 | [parallel_tool_calls](#google--gemma-4-31b-it-a100-parallel-tool-calls) | ✅ passed | parallel_tool_calls parameter accepted |
| 12 | [image_input_url](#google--gemma-4-31b-it-a100-image-input-url) | ⚠️ unsupported | Image URL input failed: Client error '424 Failed Dependency' for url 'https://go |
| 13 | [image_input_base64](#google--gemma-4-31b-it-a100-image-input-base64) | ✅ passed | Base64 image accepted and processed |
| 14 | [image_input_multi](#google--gemma-4-31b-it-a100-image-input-multi) | ✅ passed | Multiple images accepted and processed |
| 15 | [image_output](#google--gemma-4-31b-it-a100-image-output) | ❌ failed | No image content in response |
| 16 | [file_input_inline](#google--gemma-4-31b-it-a100-file-input-inline) | ➖ not applicable | Not applicable for this schema |
| 17 | [file_input_reference](#google--gemma-4-31b-it-a100-file-input-reference) | ➖ not applicable | Not applicable for this schema |
| 18 | [built_in_tools](#google--gemma-4-31b-it-a100-built-in-tools) | ➖ not applicable | Not applicable for this schema |
| 19 | [streaming](#google--gemma-4-31b-it-a100-streaming) | ✅ passed | Streaming produced 15 chunks |
| 20 | [stop_sequences](#google--gemma-4-31b-it-a100-stop-sequences) | ✅ passed | Stop sequence was respected |
| 21 | [logprobs](#google--gemma-4-31b-it-a100-logprobs) | ✅ passed | Logprobs returned with token data |
| 22 | [seeded_determinism](#google--gemma-4-31b-it-a100-seeded-determinism) | ✅ passed | Deterministic output with seed=42: '4' |
| 23 | [long_prompt_acceptance](#google--gemma-4-31b-it-a100-long-prompt-acceptance) | ✅ passed | Long prompt (22574 chars) accepted |
| 24 | [previous_response_id](#google--gemma-4-31b-it-a100-previous-response-id) | ➖ not applicable | Not applicable for this schema |
| 25 | [background_mode](#google--gemma-4-31b-it-a100-background-mode) | ➖ not applicable | Not applicable for this schema |
| 26 | [response_retrieval](#google--gemma-4-31b-it-a100-response-retrieval) | ➖ not applicable | Not applicable for this schema |
| 27 | [normalization](#google--gemma-4-31b-it-a100-normalization) | ✅ passed | Response successfully normalized |
| 28 | [regex_constraints](#google--gemma-4-31b-it-a100-regex-constraints) | ✅ passed | Output matches regex: 482-19-3057 |


## Benchmark Summary

#### H100

- **Benchmark runs:** 28
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 1154.7ms | ITL(avg): 17.1ms

#### A100

- **Benchmark runs:** 13
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 199.1ms | ITL(avg): 25.8ms


## Changelog

| Run | Status | Versions | SKUs | Duration | Steps | Failed |
|-----|--------|----------|------|----------|-------|--------|
| 2026-04-20_07-23-16 | FAILED | model=6  env=6  dt=6 | h100 a100 | 93m 19s | 7/8 passed | 7-benchmark |
| 2026-04-20_00-47-42 | FAILED | model=6  env=6  dt=6 | h100 a100 | 155m 57s | 7/8 passed | 7-benchmark |
| 2026-04-20_00-06-56 | FAILED | model=6  env=6  dt=6 | h100 a100 | 37m 35s | 6/8 passed | 6-test-inference |
| 2026-04-19_22-23-23 | FAILED | model=6  env=6  dt=6 | h100 a100 | 101m 38s | 5/8 passed | 5-create-online-deployment |
| 2026-04-19_00-02-44 | FAILED | model=1  env=1  dt=1 | h100 a100 | 35m 12s | 5/8 passed | 5-create-online-deployment |
| 2026-04-19_13-02-18 | INCOMPLETE (no summary) |  | h100 a100 | (no summary.txt) | ?/8 steps logged passed | -- |
