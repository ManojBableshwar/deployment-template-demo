# Qwen/Qwen3.5-0.8B

> Auto-generated status page — updated by E2E pipeline runs.
> Last updated: 2026-04-20 10:37:25

## Runs

<details open>
<summary><strong>2026-04-18_14-12-05</strong> — ✅ PASSED — 8/8 steps — 56m 14s</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-18_14-12-05` |
| **Status** | **PASSED** |
| **Versions** | model=50  env=50  dt=50 |
| **SKUs** | Standard_NC40ads_H100_v5 Standard_NC24ads_A100_v4 |
| **Total time** | 56m 14s |
| **Steps** | 8/8 passed |
| **Failed** | -- |

```bash

```

### Pipeline Steps

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

#### Step 0: Validate Model (PASS)

<details>
<summary>Model Artifacts</summary>

**Total:** 13 files, 1.6G

| File | Size |
|------|------|
| `model.safetensors-00001-of-00001.safetensors` | 1.6G |
| `tokenizer.json` | 12M |
| `vocab.json` | 6.4M |
| `merges.txt` | 3.2M |
| `README.md` | 60K |
| `model.safetensors.index.json` | 50K |
| `tokenizer_config.json` | 16K |
| `LICENSE` | 11K |
| `chat_template.jinja` | 7.6K |
| `config.json` | 2.8K |
| `.gitattributes` | 1.5K |
| `preprocessor_config.json` | 390B |
| `video_preprocessor_config.json` | 385B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Qwen3_5ForConditionalGeneration` |
| **Model type** | `qwen3_5` |
| **Parameters** | 873M (873,441,376) ≈ estimated from weight size |
| **Model size (weights)** | 1.63 GB (1,746,882,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 1,024 |
| **Intermediate (FFN) size** | 3,584 |
| **Num layers** | 24 |
| **Num attention heads** | 8 |
| **Num KV heads** | 2 |
| **Attention type** | Grouped-Query Attention (GQA, 4:1) |
| **Head dim** | 256 |
| **Vocab size** | 248,320 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `silu` |
| **Tie word embeddings** | True |


##### Attention Mechanism

The model uses a **hybrid attention** pattern across 24 layers:

- **Full attention:** 6 layers — attend to all tokens in the sequence
- **Linear attention:** 18 layers — O(n) complexity attention

Layer pattern (S=sliding, F=full, L=linear):
```
   0:L  1:L  2:L  3:F  4:L  5:L  6:L  7:F  8:L  9:L
  10:L 11:F 12:L 13:L 14:L 15:F 16:L 17:L 18:L 19:F
  20:L 21:L 22:L 23:F
```

**Pattern:** Every 4th layer is full attention (layers 3, 7, 11, 15, 19, 23)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **1** |
| `VLLM_MAX_MODEL_LEN` | **262,144** (256K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.9** |
| `VLLM_MAX_NUM_SEQS` | **114** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **1** (user override (--tp 1)) |
| `VLLM_MAX_MODEL_LEN` | **262,144** (256K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.9** |
| `VLLM_MAX_NUM_SEQS` | **114** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 32, 64, 114, 128, 171]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 1,746,882,752 bytes = 1.63 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 1.63/1 = 1.63 GB  <= 60.77 GB  -> YES <-- minimum TP

Result: VLLM_TENSOR_PARALLEL_SIZE = 1 (user override (--tp 1))
```

**2. GPU Memory Utilization**

```
TP = 1 -> no NCCL overhead
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.9
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 1.63 GB / 1 TP = 1.63 GB
per_gpu_kv_budget   = (80 * 0.9) - 1.63 - 0.5
                    = 72.00 - 1.63 - 0.5
                    = 69.87 GB
                    = 75,025,657,664 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(2 / 1, 1) = 2
  full_kv/tok/layer = 2 (K+V) * 2 heads * 256 dim * 2 bytes
                    = 2,048 bytes
  linear_kv/tok/lay = 2 * 16 * 128 * 2
                    = 8,192 bytes

Total KV per token (all 24 KV-bearing layers):
  = (6 full/sliding * 2048) + (18 linear * 8192)
  = 159,744 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 75,025,657,664 / 159,744 = 469,661
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(469,661, 262,144) = 262,144
  rounded (pow2)    = 2^floor(log2(262,144)) = 2^18 = 262,144

Result: VLLM_MAX_MODEL_LEN = 262,144 (256K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 469,661
  avg_seq_len       = 4096 (default assumption)
  batch             = 469,661 / 4096 = 114
  clamped           = min(max(114, 1), 256) = 114

Result: VLLM_MAX_NUM_SEQS = 114
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 114
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (>= 2, included)
    c=64 (>= 2, included)
    c=128 (> max_num_seqs, stress test)
    c=114 (= max_num_seqs, boundary)
    c=171 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 32, 64, 114, 128, 171]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **1** (user override (--tp 1)) |
| `VLLM_MAX_MODEL_LEN` | **262,144** (256K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.9** |
| `VLLM_MAX_NUM_SEQS` | **114** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 32, 64, 114, 128, 171]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 1,746,882,752 bytes = 1.63 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 1.63/1 = 1.63 GB  <= 60.77 GB  -> YES <-- minimum TP

Result: VLLM_TENSOR_PARALLEL_SIZE = 1 (user override (--tp 1))
```

**2. GPU Memory Utilization**

```
TP = 1 -> no NCCL overhead
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.9
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 1.63 GB / 1 TP = 1.63 GB
per_gpu_kv_budget   = (80 * 0.9) - 1.63 - 0.5
                    = 72.00 - 1.63 - 0.5
                    = 69.87 GB
                    = 75,025,657,664 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(2 / 1, 1) = 2
  full_kv/tok/layer = 2 (K+V) * 2 heads * 256 dim * 2 bytes
                    = 2,048 bytes
  linear_kv/tok/lay = 2 * 16 * 128 * 2
                    = 8,192 bytes

Total KV per token (all 24 KV-bearing layers):
  = (6 full/sliding * 2048) + (18 linear * 8192)
  = 159,744 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 75,025,657,664 / 159,744 = 469,661
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(469,661, 262,144) = 262,144
  rounded (pow2)    = 2^floor(log2(262,144)) = 2^18 = 262,144

Result: VLLM_MAX_MODEL_LEN = 262,144 (256K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 469,661
  avg_seq_len       = 4096 (default assumption)
  batch             = 469,661 / 4096 = 114
  clamped           = min(max(114, 1), 256) = 114

Result: VLLM_MAX_NUM_SEQS = 114
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 114
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (>= 2, included)
    c=64 (>= 2, included)
    c=128 (> max_num_seqs, stress test)
    c=114 (= max_num_seqs, boundary)
    c=171 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 32, 64, 114, 128, 171]
```

</details>

#### Step 1: Create Environment (PASS)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (PASS)

Template: `vllm-qwen--qwen3-5-0-8b` v`50` in registry `mabables-reg-feb26`

#### Step 3: Register Model (PASS)

Model: `qwen--qwen3-5-0-8b` v`50` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (PASS)

| SKU | Endpoint |
|-----|----------|
| H100 | `qwen--qwen3-5-0-8b-h100` |
| A100 | `qwen--qwen3-5-0-8b-a100` |

#### Step 5: Create Online Deployment (PASS)

Deployment: `qwen--qwen3-5-0-8b-vllm`

#### Step 6: Test Inference (PASS)

##### H100 — Received response

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

##### A100 — Received response

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

#### Step 7: Benchmark (PASS)

##### H100

- **Benchmark runs:** 28
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 160.5ms | ITL(avg): 1.9ms

##### A100

- **Benchmark runs:** 28
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 320.4ms | ITL(avg): 3.0ms

##### Benchmark Plots

###### Benchmark Avg

![Benchmark Avg](logs/e2e/2026-04-18_14-12-05/benchmark/plots/benchmark_avg.png)

###### Benchmark P50

![Benchmark P50](logs/e2e/2026-04-18_14-12-05/benchmark/plots/benchmark_p50.png)

###### Benchmark P90

![Benchmark P90](logs/e2e/2026-04-18_14-12-05/benchmark/plots/benchmark_p90.png)

<details>
<summary>Percentile breakdown by token shape</summary>

###### Percentiles Long Gen

![Percentiles Long Gen](logs/e2e/2026-04-18_14-12-05/benchmark/plots/percentiles_long_gen.png)

###### Percentiles Long Prompt

![Percentiles Long Prompt](logs/e2e/2026-04-18_14-12-05/benchmark/plots/percentiles_long_prompt.png)

###### Percentiles Short Gen

![Percentiles Short Gen](logs/e2e/2026-04-18_14-12-05/benchmark/plots/percentiles_short_gen.png)

###### Percentiles Short Prompt

![Percentiles Short Prompt](logs/e2e/2026-04-18_14-12-05/benchmark/plots/percentiles_short_prompt.png)

</details>

</details>


<details>
<summary><strong>2026-04-18_00-28-42</strong> — ❌ FAILED — 3/8 steps — unknown</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-18_00-28-42` |
| **Status** | **FAILED** |
| **Versions** |  |
| **SKUs** |  |
| **Total time** |  |
| **Steps** | 3/8 passed |
| **Failed** | 3-register-model |

```bash

```

### Pipeline Steps

```

```

#### Step 0: Validate Model (SKIP)

<details>
<summary>Model Artifacts</summary>

**Total:** 13 files, 1.6G

| File | Size |
|------|------|
| `model.safetensors-00001-of-00001.safetensors` | 1.6G |
| `tokenizer.json` | 12M |
| `vocab.json` | 6.4M |
| `merges.txt` | 3.2M |
| `README.md` | 60K |
| `model.safetensors.index.json` | 50K |
| `tokenizer_config.json` | 16K |
| `LICENSE` | 11K |
| `chat_template.jinja` | 7.6K |
| `config.json` | 2.8K |
| `.gitattributes` | 1.5K |
| `preprocessor_config.json` | 390B |
| `video_preprocessor_config.json` | 385B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Qwen3_5ForConditionalGeneration` |
| **Model type** | `qwen3_5` |
| **Parameters** | 873M (873,441,376) ≈ estimated from weight size |
| **Model size (weights)** | 1.63 GB (1,746,882,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 1,024 |
| **Intermediate (FFN) size** | 3,584 |
| **Num layers** | 24 |
| **Num attention heads** | 8 |
| **Num KV heads** | 2 |
| **Attention type** | Grouped-Query Attention (GQA, 4:1) |
| **Head dim** | 256 |
| **Vocab size** | 248,320 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `silu` |
| **Tie word embeddings** | True |


##### Attention Mechanism

The model uses a **hybrid attention** pattern across 24 layers:

- **Full attention:** 6 layers — attend to all tokens in the sequence
- **Linear attention:** 18 layers — O(n) complexity attention

Layer pattern (S=sliding, F=full, L=linear):
```
   0:L  1:L  2:L  3:F  4:L  5:L  6:L  7:F  8:L  9:L
  10:L 11:F 12:L 13:L 14:L 15:F 16:L 17:L 18:L 19:F
  20:L 21:L 22:L 23:F
```

**Pattern:** Every 4th layer is full attention (layers 3, 7, 11, 15, 19, 23)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **1** |
| `VLLM_MAX_MODEL_LEN` | **262,144** (256K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.9** |
| `VLLM_MAX_NUM_SEQS` | **114** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **1** (user override (--tp 1)) |
| `VLLM_MAX_MODEL_LEN` | **262,144** (256K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.9** |
| `VLLM_MAX_NUM_SEQS` | **114** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 32, 64, 114, 128, 171]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 1,746,882,752 bytes = 1.63 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 1.63/1 = 1.63 GB  <= 60.77 GB  -> YES <-- minimum TP

Result: VLLM_TENSOR_PARALLEL_SIZE = 1 (user override (--tp 1))
```

**2. GPU Memory Utilization**

```
TP = 1 -> no NCCL overhead
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.9
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 1.63 GB / 1 TP = 1.63 GB
per_gpu_kv_budget   = (80 * 0.9) - 1.63 - 0.5
                    = 72.00 - 1.63 - 0.5
                    = 69.87 GB
                    = 75,025,657,664 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(2 / 1, 1) = 2
  full_kv/tok/layer = 2 (K+V) * 2 heads * 256 dim * 2 bytes
                    = 2,048 bytes
  linear_kv/tok/lay = 2 * 16 * 128 * 2
                    = 8,192 bytes

Total KV per token (all 24 KV-bearing layers):
  = (6 full/sliding * 2048) + (18 linear * 8192)
  = 159,744 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 75,025,657,664 / 159,744 = 469,661
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(469,661, 262,144) = 262,144
  rounded (pow2)    = 2^floor(log2(262,144)) = 2^18 = 262,144

Result: VLLM_MAX_MODEL_LEN = 262,144 (256K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 469,661
  avg_seq_len       = 4096 (default assumption)
  batch             = 469,661 / 4096 = 114
  clamped           = min(max(114, 1), 256) = 114

Result: VLLM_MAX_NUM_SEQS = 114
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 114
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (>= 2, included)
    c=64 (>= 2, included)
    c=128 (> max_num_seqs, stress test)
    c=114 (= max_num_seqs, boundary)
    c=171 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 32, 64, 114, 128, 171]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **1** (user override (--tp 1)) |
| `VLLM_MAX_MODEL_LEN` | **262,144** (256K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.9** |
| `VLLM_MAX_NUM_SEQS` | **114** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 32, 64, 114, 128, 171]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 1,746,882,752 bytes = 1.63 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 1.63/1 = 1.63 GB  <= 60.77 GB  -> YES <-- minimum TP

Result: VLLM_TENSOR_PARALLEL_SIZE = 1 (user override (--tp 1))
```

**2. GPU Memory Utilization**

```
TP = 1 -> no NCCL overhead
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.9
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 1.63 GB / 1 TP = 1.63 GB
per_gpu_kv_budget   = (80 * 0.9) - 1.63 - 0.5
                    = 72.00 - 1.63 - 0.5
                    = 69.87 GB
                    = 75,025,657,664 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(2 / 1, 1) = 2
  full_kv/tok/layer = 2 (K+V) * 2 heads * 256 dim * 2 bytes
                    = 2,048 bytes
  linear_kv/tok/lay = 2 * 16 * 128 * 2
                    = 8,192 bytes

Total KV per token (all 24 KV-bearing layers):
  = (6 full/sliding * 2048) + (18 linear * 8192)
  = 159,744 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 75,025,657,664 / 159,744 = 469,661
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(469,661, 262,144) = 262,144
  rounded (pow2)    = 2^floor(log2(262,144)) = 2^18 = 262,144

Result: VLLM_MAX_MODEL_LEN = 262,144 (256K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 469,661
  avg_seq_len       = 4096 (default assumption)
  batch             = 469,661 / 4096 = 114
  clamped           = min(max(114, 1), 256) = 114

Result: VLLM_MAX_NUM_SEQS = 114
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 114
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (>= 2, included)
    c=64 (>= 2, included)
    c=128 (> max_num_seqs, stress test)
    c=114 (= max_num_seqs, boundary)
    c=171 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 32, 64, 114, 128, 171]
```

</details>

#### Step 1: Create Environment (SKIP)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (SKIP)

Template: `vllm-qwen--qwen3-5-0-8b` v`50` in registry `mabables-reg-feb26`

#### Step 3: Register Model (SKIP)

Model: `qwen--qwen3-5-0-8b` v`50` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (SKIP)

| SKU | Endpoint |
|-----|----------|
| H100 | `qwen--qwen3-5-0-8b-h100` |
| A100 | `qwen--qwen3-5-0-8b-a100` |

#### Step 5: Create Online Deployment (SKIP)

Deployment: `qwen--qwen3-5-0-8b-vllm`

#### Step 6: Test Inference (SKIP)

#### Step 7: Benchmark (SKIP)


</details>


<details>
<summary><strong>2026-04-17_19-45-20</strong> — ⚠️ INCOMPLETE (no summary) — ?/7 steps — unknown</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-17_19-45-20` |
| **Status** | **INCOMPLETE (no summary)** |
| **Versions** |  |
| **SKUs** |  |
| **Total time** | unknown |
| **Steps** | ?/7 passed |
| **Failed** | -- |

```bash

```

### Pipeline Steps

```

```

#### Step 0: Validate Model (SKIP)

<details>
<summary>Model Artifacts</summary>

**Total:** 13 files, 1.6G

| File | Size |
|------|------|
| `model.safetensors-00001-of-00001.safetensors` | 1.6G |
| `tokenizer.json` | 12M |
| `vocab.json` | 6.4M |
| `merges.txt` | 3.2M |
| `README.md` | 60K |
| `model.safetensors.index.json` | 50K |
| `tokenizer_config.json` | 16K |
| `LICENSE` | 11K |
| `chat_template.jinja` | 7.6K |
| `config.json` | 2.8K |
| `.gitattributes` | 1.5K |
| `preprocessor_config.json` | 390B |
| `video_preprocessor_config.json` | 385B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Qwen3_5ForConditionalGeneration` |
| **Model type** | `qwen3_5` |
| **Parameters** | 873M (873,441,376) ≈ estimated from weight size |
| **Model size (weights)** | 1.63 GB (1,746,882,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 1,024 |
| **Intermediate (FFN) size** | 3,584 |
| **Num layers** | 24 |
| **Num attention heads** | 8 |
| **Num KV heads** | 2 |
| **Attention type** | Grouped-Query Attention (GQA, 4:1) |
| **Head dim** | 256 |
| **Vocab size** | 248,320 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `silu` |
| **Tie word embeddings** | True |


##### Attention Mechanism

The model uses a **hybrid attention** pattern across 24 layers:

- **Full attention:** 6 layers — attend to all tokens in the sequence
- **Linear attention:** 18 layers — O(n) complexity attention

Layer pattern (S=sliding, F=full, L=linear):
```
   0:L  1:L  2:L  3:F  4:L  5:L  6:L  7:F  8:L  9:L
  10:L 11:F 12:L 13:L 14:L 15:F 16:L 17:L 18:L 19:F
  20:L 21:L 22:L 23:F
```

**Pattern:** Every 4th layer is full attention (layers 3, 7, 11, 15, 19, 23)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **1** |
| `VLLM_MAX_MODEL_LEN` | **262,144** (256K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.9** |
| `VLLM_MAX_NUM_SEQS` | **114** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **1** (user override (--tp 1)) |
| `VLLM_MAX_MODEL_LEN` | **262,144** (256K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.9** |
| `VLLM_MAX_NUM_SEQS` | **114** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 32, 64, 114, 128, 171]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 1,746,882,752 bytes = 1.63 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 1.63/1 = 1.63 GB  <= 60.77 GB  -> YES <-- minimum TP

Result: VLLM_TENSOR_PARALLEL_SIZE = 1 (user override (--tp 1))
```

**2. GPU Memory Utilization**

```
TP = 1 -> no NCCL overhead
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.9
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 1.63 GB / 1 TP = 1.63 GB
per_gpu_kv_budget   = (80 * 0.9) - 1.63 - 0.5
                    = 72.00 - 1.63 - 0.5
                    = 69.87 GB
                    = 75,025,657,664 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(2 / 1, 1) = 2
  full_kv/tok/layer = 2 (K+V) * 2 heads * 256 dim * 2 bytes
                    = 2,048 bytes
  linear_kv/tok/lay = 2 * 16 * 128 * 2
                    = 8,192 bytes

Total KV per token (all 24 KV-bearing layers):
  = (6 full/sliding * 2048) + (18 linear * 8192)
  = 159,744 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 75,025,657,664 / 159,744 = 469,661
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(469,661, 262,144) = 262,144
  rounded (pow2)    = 2^floor(log2(262,144)) = 2^18 = 262,144

Result: VLLM_MAX_MODEL_LEN = 262,144 (256K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 469,661
  avg_seq_len       = 4096 (default assumption)
  batch             = 469,661 / 4096 = 114
  clamped           = min(max(114, 1), 256) = 114

Result: VLLM_MAX_NUM_SEQS = 114
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 114
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (>= 2, included)
    c=64 (>= 2, included)
    c=128 (> max_num_seqs, stress test)
    c=114 (= max_num_seqs, boundary)
    c=171 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 32, 64, 114, 128, 171]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **1** (user override (--tp 1)) |
| `VLLM_MAX_MODEL_LEN` | **262,144** (256K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.9** |
| `VLLM_MAX_NUM_SEQS` | **114** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 32, 64, 114, 128, 171]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 1,746,882,752 bytes = 1.63 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 1.63/1 = 1.63 GB  <= 60.77 GB  -> YES <-- minimum TP

Result: VLLM_TENSOR_PARALLEL_SIZE = 1 (user override (--tp 1))
```

**2. GPU Memory Utilization**

```
TP = 1 -> no NCCL overhead
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.9
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 1.63 GB / 1 TP = 1.63 GB
per_gpu_kv_budget   = (80 * 0.9) - 1.63 - 0.5
                    = 72.00 - 1.63 - 0.5
                    = 69.87 GB
                    = 75,025,657,664 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(2 / 1, 1) = 2
  full_kv/tok/layer = 2 (K+V) * 2 heads * 256 dim * 2 bytes
                    = 2,048 bytes
  linear_kv/tok/lay = 2 * 16 * 128 * 2
                    = 8,192 bytes

Total KV per token (all 24 KV-bearing layers):
  = (6 full/sliding * 2048) + (18 linear * 8192)
  = 159,744 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 75,025,657,664 / 159,744 = 469,661
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(469,661, 262,144) = 262,144
  rounded (pow2)    = 2^floor(log2(262,144)) = 2^18 = 262,144

Result: VLLM_MAX_MODEL_LEN = 262,144 (256K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 469,661
  avg_seq_len       = 4096 (default assumption)
  batch             = 469,661 / 4096 = 114
  clamped           = min(max(114, 1), 256) = 114

Result: VLLM_MAX_NUM_SEQS = 114
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 114
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (>= 2, included)
    c=64 (>= 2, included)
    c=128 (> max_num_seqs, stress test)
    c=114 (= max_num_seqs, boundary)
    c=171 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 32, 64, 114, 128, 171]
```

</details>

#### Step 1: Create Environment (SKIP)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (SKIP)

Template: `vllm-qwen--qwen3-5-0-8b` v`50` in registry `mabables-reg-feb26`

#### Step 3: Register Model (SKIP)

Model: `qwen--qwen3-5-0-8b` v`50` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (SKIP)

| SKU | Endpoint |
|-----|----------|
| H100 | `qwen--qwen3-5-0-8b-h100` |
| A100 | `qwen--qwen3-5-0-8b-a100` |

#### Step 5: Create Online Deployment (SKIP)

Deployment: `qwen--qwen3-5-0-8b-vllm`

#### Step 6: Test Inference (SKIP)

##### H100 — Received response

<details>
<summary>Response snippet</summary>

```json
    "choices": [
        {
            "index": 0,
            "message": {
                "role": "assistant",
                "content": "Large Language Models (LLMs) are sophisticated neural architectures built on the principle of **transformer architecture**, which allow them to process massive datasets of text and output relevant responses. Unlike earlier, rule-based systems, LLMs are trained on massive datasets of text, distinguishing them from traditional models that can parse rules or perform a limited range of tasks (like math or logic).\n\nTheir core strength lies in their flexibility: they can understand, generate, maintain, and reason with documents, often outperforming human interns in many scenarios. However, their primary limitation is **stop-and-generate**, meaning they lack the reasoning capabilities needed to explore and plan multiple alternatives to solve a complex problem, making prompt engineering crucial for achieving higher performance in specific tasks.",
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

#### Step 7: Benchmark (SKIP)

##### H100

- **Benchmark runs:** 27
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 167.4ms | ITL(avg): 1.9ms


</details>



## Changelog

| Run | Status | Versions | SKUs | Duration | Steps | Failed |
|-----|--------|----------|------|----------|-------|--------|
| 2026-04-18_14-12-05 | PASSED | model=50  env=50  dt=50 | Standard_NC40ads_H100_v5 Standard_NC24ads_A100_v4 | 56m 14s | 8/8 passed | -- |
| 2026-04-18_00-28-42 | FAILED |  |  |  | 3/8 passed | 3-register-model |
| 2026-04-17_19-45-20 | INCOMPLETE | | | | | |
