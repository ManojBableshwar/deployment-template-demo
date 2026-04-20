# Qwen/Qwen3.5-0.8B

> Auto-generated status page — updated by E2E pipeline runs.
> Last updated: 2026-04-19 22:20:29

## Latest Run

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-18_14-12-05` |
| **Status** | **PASSED** |
| **Versions** | model=50  env=50  dt=50 |
| **SKUs** | Standard_NC40ads_H100_v5 Standard_NC24ads_A100_v4 |
| **Total time** | 56m 14s |
| **Steps** | 8/8 passed |
| **Failed** | -- |

### Command

```bash

```

### Step Results

```
  STEP                                      TIME  STATUS    ACTION
  0-validate-model                          0m 01s  [PASS]  CREATED
  1-create-environment                      0m 43s  [PASS]  SKIPPED (asset already exists)
  2-create-deployment-template              0m 08s  [PASS]  SKIPPED (asset already exists)
  3-register-model                          2m 21s  [PASS]  CREATED
  4-create-online-endpoint                  1m 17s  [PASS]  CREATED
    └─ h100                                 1m 10s          CREATED
    └─ a100                                 1m 10s          CREATED
  5-create-online-deployment               22m 44s  [PASS]  CREATED
    └─ h100                                21m 50s          CREATED
    └─ a100                                22m 25s          CREATED
  6-test-inference                          0m 18s  [PASS]  CREATED
    └─ h100                                 0m 08s          CREATED
    └─ a100                                 0m 09s          CREATED
  7-benchmark                             28m 42s  [PASS]  CREATED
    └─ h100                                20m 19s          CREATED
    └─ a100                                28m 20s          CREATED
```

## Inference API Tests

#### H100 — Received response

<details>
<summary>Response snippet</summary>

```json
    "choices": [
        {
            "index": 0,
            "message": {
                "role": "assistant",
                "content": "Large Language Models (LLMs) are massive neural networks trained on vast amounts of text data, capable of generating human-like text across diverse domains like writing code, legal documents, creative writing, and dialogue.\n\nTheir power comes from training on **natural language** corpora\u2014emails, novels, news articles, and legal contracts\u2014rather than restricted patterns like spoken language. Transformers enable their ability to understand context, extract meaning, and reason from long-form material. While currently limited by memory with some conversational tasks, they have revolutionized AI applications since their inception in 2017, forming the backbone of modern big data processing, social media, virtual assistants, and personalized content generation.",
                "refusal": null,
                "annotations": null,
                "audio": null,
                "function_call": null,
                "tool_calls": [],
                "reasoning": null
            },
            "logprobs": null,
            "finish_reason": "stop",
```

</details>

#### A100 — Received response

<details>
<summary>Response snippet</summary>

```json
    "choices": [
        {
            "index": 0,
            "message": {
                "role": "assistant",
                "content": "Large Language Models (LLMs) are massive neural networks trained on vast amounts of text data, capable of generating human-like text across diverse domains like writing code, legal documents, creative writing, and dialogue.\n\nTheir power comes from training on **natural language** corpora\u2014emails, novels, news articles, and legal contracts\u2014rather than restricted patterns like spoken language. Transformers enable their ability to understand context, extract meaning, and reason from long-form material. While currently limited by memory with some conversational tasks, they have revolutionized AI applications since their inception in 2017, forming the backbone of modern big data processing, social media, virtual assistants, and personalized content generation.",
                "refusal": null,
                "annotations": null,
                "audio": null,
                "function_call": null,
                "tool_calls": [],
                "reasoning": null
            },
            "logprobs": null,
            "finish_reason": "stop",
```

</details>


## Benchmark Summary

#### H100

- **Benchmark runs:** 28
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 160.5ms | ITL(avg): 1.9ms

#### A100

- **Benchmark runs:** 28
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 320.4ms | ITL(avg): 3.0ms


### Benchmark Plots

#### Benchmark Avg

![Benchmark Avg](logs/e2e/2026-04-18_14-12-05/benchmark/plots/benchmark_avg.png)

#### Benchmark P50

![Benchmark P50](logs/e2e/2026-04-18_14-12-05/benchmark/plots/benchmark_p50.png)

#### Benchmark P90

![Benchmark P90](logs/e2e/2026-04-18_14-12-05/benchmark/plots/benchmark_p90.png)

<details>
<summary>Percentile breakdown by token shape</summary>

#### Percentiles Long Gen

![Percentiles Long Gen](logs/e2e/2026-04-18_14-12-05/benchmark/plots/percentiles_long_gen.png)

#### Percentiles Long Prompt

![Percentiles Long Prompt](logs/e2e/2026-04-18_14-12-05/benchmark/plots/percentiles_long_prompt.png)

#### Percentiles Short Gen

![Percentiles Short Gen](logs/e2e/2026-04-18_14-12-05/benchmark/plots/percentiles_short_gen.png)

#### Percentiles Short Prompt

![Percentiles Short Prompt](logs/e2e/2026-04-18_14-12-05/benchmark/plots/percentiles_short_prompt.png)

</details>


## Changelog

| Run | Status | Versions | SKUs | Duration | Steps | Failed |
|-----|--------|----------|------|----------|-------|--------|
| 2026-04-18_14-12-05 | PASSED | model=50  env=50  dt=50 | Standard_NC40ads_H100_v5 Standard_NC24ads_A100_v4 | 56m 14s | 8/8 passed | -- |
| 2026-04-18_00-28-42 | FAILED |  |  |  | 3/8 passed | 3-register-model |
| 2026-04-17_19-45-20 | INCOMPLETE (no summary) |  | h100 | (no summary.txt) | ?/7 steps logged passed | -- |
