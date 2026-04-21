# google/gemma-4-31B-it

> Auto-generated status page — updated by E2E pipeline runs.
> Last updated: 2026-04-20 10:37:43

## Runs

<details open>
<summary><strong>2026-04-20_07-23-16</strong> — ❌ FAILED — 7/8 steps — 93m 19s</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-20_07-23-16` |
| **Status** | **FAILED** |
| **Versions** | model=6  env=6  dt=6 |
| **SKUs** | h100 a100 |
| **Total time** | 93m 19s |
| **Steps** | 7/8 passed |
| **Failed** | 7-benchmark |

```bash
azureml-deployment-templates/scripts/run-e2e-cli.sh --hf-model google/gemma-4-31B-it --version 6 --tp 2 --sku Standard_NC80adis_H100_v5 --sku Standard_NC48ads_A100_v4
```

### Pipeline Steps

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

#### Step 0: Validate Model (PASS)

<details>
<summary>Model Artifacts</summary>

**Total:** 11 files,  58G

| File | Size |
|------|------|
| `model-00001-of-00002.safetensors` | 46G |
| `model-00002-of-00002.safetensors` | 12G |
| `tokenizer.json` | 31M |
| `model.safetensors.index.json` | 117K |
| `README.md` | 26K |
| `chat_template.jinja` | 16K |
| `config.json` | 4.5K |
| `tokenizer_config.json` | 2.0K |
| `.gitattributes` | 1.7K |
| `processor_config.json` | 1.6K |
| `generation_config.json` | 208B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Gemma4ForConditionalGeneration` |
| **Model type** | `gemma4` |
| **Parameters** | 32.7B (32,682,372,656) |
| **Model size (weights)** | 58.25 GB (62,546,177,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 5,376 |
| **Intermediate (FFN) size** | 21,504 |
| **Num layers** | 60 |
| **Num attention heads** | 32 |
| **Num KV heads** | 16 |
| **Attention type** | Grouped-Query Attention (GQA, 2:1) |
| **Head dim** | 256 |
| **Global head dim** | 512 |
| **Vocab size** | 262,144 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `gelu_pytorch_tanh` |
| **Tie word embeddings** | True |
| **Sliding window** | 1,024 tokens |
| **Vision encoder** | 27 layers, hidden=1152, heads=16, patch=16 |

> **Weight size derivation:**
>   Parameters × 2 bytes = 65,364,745,312 bytes (60.88 GB), but `tie_word_embeddings=true` means the embedding matrix (vocab × hidden = 262,144 × 5,376 = 1,409,286,144 params, 2.62 GB) is stored once on disk instead of twice (input embed + LM head). Disk size = 65,364,745,312 − 2,818,572,288 = 62,546,173,024 bytes ≈ 62,546,177,752 bytes (58.25 GB).

##### Attention Mechanism

The model uses a **hybrid attention** pattern across 60 layers:

- **Full attention:** 10 layers — attend to all tokens in the sequence
- **Sliding window attention:** 50 layers — attend to local window of 1024 tokens

Layer pattern (S=sliding, F=full, L=linear):
```
   0:S  1:S  2:S  3:S  4:S  5:F  6:S  7:S  8:S  9:S
  10:S 11:F 12:S 13:S 14:S 15:S 16:S 17:F 18:S 19:S
  20:S 21:S 22:S 23:F 24:S 25:S 26:S 27:S 28:S 29:F
  30:S 31:S 32:S 33:S 34:S 35:F 36:S 37:S 38:S 39:S
  40:S 41:F 42:S 43:S 44:S 45:S 46:S 47:F 48:S 49:S
  50:S 51:S 52:S 53:F 54:S 55:S 56:S 57:S 58:S 59:F
```

**Pattern:** Every 6th layer is full attention (layers 5, 11, 17, 23, 29, 35, 41, 47, 53, 59)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

##### Persisted Benchmark Config

From `yaml/benchmark-config.yml` (hydrated by step 2, used by step 7):

| Setting | Value |
|---------|-------|
| Concurrencies | `[2, 4, 8, 16, 20, 30, 32]` |
| Max num seqs | `20` |

#### Step 1: Create Environment (PASS)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (PASS)

Template: `vllm-google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 3: Register Model (PASS)

Model: `google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (PASS)

| SKU | Endpoint |
|-----|----------|
| H100 | `google--gemma-4-31b-it-h100` |
| A100 | `google--gemma-4-31b-it-a100` |

#### Step 5: Create Online Deployment (PASS)

Deployment: `google--gemma-4-31b-it-vllm`

#### Step 6: Test Inference (PASS)

##### H100 — llm-api-spec results

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
| 29 | [grammar_constraints](#google--gemma-4-31b-it-h100-grammar-constraints) | ⚠️ unsupported | Grammar constraints check failed: Client error '424 Failed Dependency' for url ' |
| 30 | [json_schema_constraints](#google--gemma-4-31b-it-h100-json-schema-constraints) | ✅ passed | JSON schema constraint enforced correctly |

##### A100 — llm-api-spec results

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
| 29 | [grammar_constraints](#google--gemma-4-31b-it-a100-grammar-constraints) | ⚠️ unsupported | Grammar constraints check failed: Client error '424 Failed Dependency' for url ' |
| 30 | [json_schema_constraints](#google--gemma-4-31b-it-a100-json-schema-constraints) | ✅ passed | JSON schema constraint enforced correctly |

#### Step 7: Benchmark (FAIL)

##### H100

- **Benchmark runs:** 28
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 1154.7ms | ITL(avg): 17.1ms

##### A100

- **Benchmark runs:** 13
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 199.1ms | ITL(avg): 25.8ms

##### Benchmark Plots

###### Benchmark Avg

![Benchmark Avg](logs/e2e/2026-04-20_07-23-16/benchmark/plots/benchmark_avg.png)

###### Benchmark P50

![Benchmark P50](logs/e2e/2026-04-20_07-23-16/benchmark/plots/benchmark_p50.png)

###### Benchmark P90

![Benchmark P90](logs/e2e/2026-04-20_07-23-16/benchmark/plots/benchmark_p90.png)

###### Errors

![Errors](logs/e2e/2026-04-20_07-23-16/benchmark/plots/errors.png)

<details>
<summary>Percentile breakdown by token shape</summary>

###### Percentiles Long Gen

![Percentiles Long Gen](logs/e2e/2026-04-20_07-23-16/benchmark/plots/percentiles_long_gen.png)

###### Percentiles Long Prompt

![Percentiles Long Prompt](logs/e2e/2026-04-20_07-23-16/benchmark/plots/percentiles_long_prompt.png)

###### Percentiles Short Gen

![Percentiles Short Gen](logs/e2e/2026-04-20_07-23-16/benchmark/plots/percentiles_short_gen.png)

###### Percentiles Short Prompt

![Percentiles Short Prompt](logs/e2e/2026-04-20_07-23-16/benchmark/plots/percentiles_short_prompt.png)

</details>

</details>


<details>
<summary><strong>2026-04-20_00-47-42</strong> — ❌ FAILED — 7/8 steps — 155m 57s</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-20_00-47-42` |
| **Status** | **FAILED** |
| **Versions** | model=6  env=6  dt=6 |
| **SKUs** | h100 a100 |
| **Total time** | 155m 57s |
| **Steps** | 7/8 passed |
| **Failed** | 7-benchmark |

```bash
azureml-deployment-templates/scripts/run-e2e-cli.sh --hf-model google/gemma-4-31B-it --version 6 --tp 2 --sku Standard_NC80adis_H100_v5 --sku Standard_NC48ads_A100_v4
```

### Pipeline Steps

```
  STEP                                      TIME  STATUS    ACTION
  0-validate-model                          0m 01s  [PASS]    CREATED
  1-create-environment                      0m 12s  [PASS]    CREATED
  2-create-deployment-template              0m 08s  [PASS]    CREATED
  3-register-model                          0m 07s  [PASS]    CREATED
  4-create-online-endpoint                  0m 09s  [PASS]    CREATED
    └─ a100                                 0m 03s            CREATED
    └─ h100                                 0m 03s            CREATED
  5-create-online-deployment                0m 08s  [PASS]    CREATED
    └─ a100                                 0m 03s            CREATED
    └─ h100                                 0m 03s            CREATED
  6-test-inference                          1m 11s  [PASS]    CREATED
    └─ debug                                0m 20s            CREATED
    └─ a100                                 0m 40s            CREATED
    └─ debug                                0m 15s            CREATED
    └─ h100                                 0m 31s            CREATED
  7-benchmark                             154m 01s  [FAIL]  
    └─ a100                               153m 42s            CREATED
    └─ h100                                83m 41s            CREATED
```

#### Step 0: Validate Model (PASS)

<details>
<summary>Model Artifacts</summary>

**Total:** 11 files,  58G

| File | Size |
|------|------|
| `model-00001-of-00002.safetensors` | 46G |
| `model-00002-of-00002.safetensors` | 12G |
| `tokenizer.json` | 31M |
| `model.safetensors.index.json` | 117K |
| `README.md` | 26K |
| `chat_template.jinja` | 16K |
| `config.json` | 4.5K |
| `tokenizer_config.json` | 2.0K |
| `.gitattributes` | 1.7K |
| `processor_config.json` | 1.6K |
| `generation_config.json` | 208B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Gemma4ForConditionalGeneration` |
| **Model type** | `gemma4` |
| **Parameters** | 32.7B (32,682,372,656) |
| **Model size (weights)** | 58.25 GB (62,546,177,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 5,376 |
| **Intermediate (FFN) size** | 21,504 |
| **Num layers** | 60 |
| **Num attention heads** | 32 |
| **Num KV heads** | 16 |
| **Attention type** | Grouped-Query Attention (GQA, 2:1) |
| **Head dim** | 256 |
| **Global head dim** | 512 |
| **Vocab size** | 262,144 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `gelu_pytorch_tanh` |
| **Tie word embeddings** | True |
| **Sliding window** | 1,024 tokens |
| **Vision encoder** | 27 layers, hidden=1152, heads=16, patch=16 |

> **Weight size derivation:**
>   Parameters × 2 bytes = 65,364,745,312 bytes (60.88 GB), but `tie_word_embeddings=true` means the embedding matrix (vocab × hidden = 262,144 × 5,376 = 1,409,286,144 params, 2.62 GB) is stored once on disk instead of twice (input embed + LM head). Disk size = 65,364,745,312 − 2,818,572,288 = 62,546,173,024 bytes ≈ 62,546,177,752 bytes (58.25 GB).

##### Attention Mechanism

The model uses a **hybrid attention** pattern across 60 layers:

- **Full attention:** 10 layers — attend to all tokens in the sequence
- **Sliding window attention:** 50 layers — attend to local window of 1024 tokens

Layer pattern (S=sliding, F=full, L=linear):
```
   0:S  1:S  2:S  3:S  4:S  5:F  6:S  7:S  8:S  9:S
  10:S 11:F 12:S 13:S 14:S 15:S 16:S 17:F 18:S 19:S
  20:S 21:S 22:S 23:F 24:S 25:S 26:S 27:S 28:S 29:F
  30:S 31:S 32:S 33:S 34:S 35:F 36:S 37:S 38:S 39:S
  40:S 41:F 42:S 43:S 44:S 45:S 46:S 47:F 48:S 49:S
  50:S 51:S 52:S 53:F 54:S 55:S 56:S 57:S 58:S 59:F
```

**Pattern:** Every 6th layer is full attention (layers 5, 11, 17, 23, 29, 35, 41, 47, 53, 59)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

##### Persisted Benchmark Config

From `yaml/benchmark-config.yml` (hydrated by step 2, used by step 7):

| Setting | Value |
|---------|-------|
| Concurrencies | `[2, 4, 8, 16, 20, 30, 32]` |
| Max num seqs | `20` |

#### Step 1: Create Environment (PASS)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (PASS)

Template: `vllm-google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 3: Register Model (PASS)

Model: `google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (PASS)

| SKU | Endpoint |
|-----|----------|
| H100 | `google--gemma-4-31b-it-h100` |
| A100 | `google--gemma-4-31b-it-a100` |

#### Step 5: Create Online Deployment (PASS)

Deployment: `google--gemma-4-31b-it-vllm`

#### Step 6: Test Inference (PASS)

##### H100 — llm-api-spec results

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
| 28 | [regex_constraints](#google--gemma-4-31b-it-h100-regex-constraints) | ✅ passed | Output matches regex: 472-81-9305 |
| 29 | [grammar_constraints](#google--gemma-4-31b-it-h100-grammar-constraints) | ⚠️ unsupported | Grammar constraints check failed: Client error '424 Failed Dependency' for url ' |
| 30 | [json_schema_constraints](#google--gemma-4-31b-it-h100-json-schema-constraints) | ✅ passed | JSON schema constraint enforced correctly |

##### A100 — llm-api-spec results

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
| 28 | [regex_constraints](#google--gemma-4-31b-it-a100-regex-constraints) | ✅ passed | Output matches regex: 482-19-6307 |
| 29 | [grammar_constraints](#google--gemma-4-31b-it-a100-grammar-constraints) | ⚠️ unsupported | Grammar constraints check failed: Client error '424 Failed Dependency' for url ' |
| 30 | [json_schema_constraints](#google--gemma-4-31b-it-a100-json-schema-constraints) | ✅ passed | JSON schema constraint enforced correctly |

#### Step 7: Benchmark (FAIL)

##### H100

- **Benchmark runs:** 28
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 1165.8ms | ITL(avg): 17.1ms

##### A100

- **Benchmark runs:** 13
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 211.5ms | ITL(avg): 25.8ms

##### Benchmark Plots

###### Benchmark Avg

![Benchmark Avg](logs/e2e/2026-04-20_00-47-42/benchmark/plots/benchmark_avg.png)

###### Benchmark P50

![Benchmark P50](logs/e2e/2026-04-20_00-47-42/benchmark/plots/benchmark_p50.png)

###### Benchmark P90

![Benchmark P90](logs/e2e/2026-04-20_00-47-42/benchmark/plots/benchmark_p90.png)

###### Errors

![Errors](logs/e2e/2026-04-20_00-47-42/benchmark/plots/errors.png)

<details>
<summary>Percentile breakdown by token shape</summary>

###### Percentiles Long Gen

![Percentiles Long Gen](logs/e2e/2026-04-20_00-47-42/benchmark/plots/percentiles_long_gen.png)

###### Percentiles Long Prompt

![Percentiles Long Prompt](logs/e2e/2026-04-20_00-47-42/benchmark/plots/percentiles_long_prompt.png)

###### Percentiles Short Gen

![Percentiles Short Gen](logs/e2e/2026-04-20_00-47-42/benchmark/plots/percentiles_short_gen.png)

###### Percentiles Short Prompt

![Percentiles Short Prompt](logs/e2e/2026-04-20_00-47-42/benchmark/plots/percentiles_short_prompt.png)

</details>

</details>


<details>
<summary><strong>2026-04-20_00-06-56</strong> — ❌ FAILED — 6/8 steps — 37m 35s</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-20_00-06-56` |
| **Status** | **FAILED** |
| **Versions** | model=6  env=6  dt=6 |
| **SKUs** | h100 a100 |
| **Total time** | 37m 35s |
| **Steps** | 6/8 passed |
| **Failed** | 6-test-inference |

```bash
azureml-deployment-templates/scripts/run-e2e-cli.sh --hf-model google/gemma-4-31B-it --version 6 --tp 2 --sku Standard_NC80adis_H100_v5 --sku Standard_NC48ads_A100_v4
```

### Pipeline Steps

```
  STEP                                      TIME  STATUS    ACTION
  0-validate-model                          0m 01s  [PASS]    CREATED
  1-create-environment                      0m 13s  [PASS]    CREATED
  2-create-deployment-template              0m 07s  [PASS]    CREATED
  3-register-model                          0m 07s  [PASS]    CREATED
  4-create-online-endpoint                  0m 09s  [PASS]    CREATED
    └─ a100                                 0m 03s            CREATED
    └─ h100                                 0m 03s            CREATED
  5-create-online-deployment               36m 58s  [PASS]    CREATED
    └─ a100                                36m 39s            CREATED
    └─ h100                                30m 52s            CREATED
  6-test-inference                          0m 00s  [FAIL]  
```

#### Step 0: Validate Model (PASS)

<details>
<summary>Model Artifacts</summary>

**Total:** 11 files,  58G

| File | Size |
|------|------|
| `model-00001-of-00002.safetensors` | 46G |
| `model-00002-of-00002.safetensors` | 12G |
| `tokenizer.json` | 31M |
| `model.safetensors.index.json` | 117K |
| `README.md` | 26K |
| `chat_template.jinja` | 16K |
| `config.json` | 4.5K |
| `tokenizer_config.json` | 2.0K |
| `.gitattributes` | 1.7K |
| `processor_config.json` | 1.6K |
| `generation_config.json` | 208B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Gemma4ForConditionalGeneration` |
| **Model type** | `gemma4` |
| **Parameters** | 32.7B (32,682,372,656) |
| **Model size (weights)** | 58.25 GB (62,546,177,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 5,376 |
| **Intermediate (FFN) size** | 21,504 |
| **Num layers** | 60 |
| **Num attention heads** | 32 |
| **Num KV heads** | 16 |
| **Attention type** | Grouped-Query Attention (GQA, 2:1) |
| **Head dim** | 256 |
| **Global head dim** | 512 |
| **Vocab size** | 262,144 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `gelu_pytorch_tanh` |
| **Tie word embeddings** | True |
| **Sliding window** | 1,024 tokens |
| **Vision encoder** | 27 layers, hidden=1152, heads=16, patch=16 |

> **Weight size derivation:**
>   Parameters × 2 bytes = 65,364,745,312 bytes (60.88 GB), but `tie_word_embeddings=true` means the embedding matrix (vocab × hidden = 262,144 × 5,376 = 1,409,286,144 params, 2.62 GB) is stored once on disk instead of twice (input embed + LM head). Disk size = 65,364,745,312 − 2,818,572,288 = 62,546,173,024 bytes ≈ 62,546,177,752 bytes (58.25 GB).

##### Attention Mechanism

The model uses a **hybrid attention** pattern across 60 layers:

- **Full attention:** 10 layers — attend to all tokens in the sequence
- **Sliding window attention:** 50 layers — attend to local window of 1024 tokens

Layer pattern (S=sliding, F=full, L=linear):
```
   0:S  1:S  2:S  3:S  4:S  5:F  6:S  7:S  8:S  9:S
  10:S 11:F 12:S 13:S 14:S 15:S 16:S 17:F 18:S 19:S
  20:S 21:S 22:S 23:F 24:S 25:S 26:S 27:S 28:S 29:F
  30:S 31:S 32:S 33:S 34:S 35:F 36:S 37:S 38:S 39:S
  40:S 41:F 42:S 43:S 44:S 45:S 46:S 47:F 48:S 49:S
  50:S 51:S 52:S 53:F 54:S 55:S 56:S 57:S 58:S 59:F
```

**Pattern:** Every 6th layer is full attention (layers 5, 11, 17, 23, 29, 35, 41, 47, 53, 59)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

##### Persisted Benchmark Config

From `yaml/benchmark-config.yml` (hydrated by step 2, used by step 7):

| Setting | Value |
|---------|-------|
| Concurrencies | `[2, 4, 8, 16, 20, 30, 32]` |
| Max num seqs | `20` |

#### Step 1: Create Environment (PASS)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (PASS)

Template: `vllm-google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 3: Register Model (PASS)

Model: `google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (PASS)

| SKU | Endpoint |
|-----|----------|
| H100 | `google--gemma-4-31b-it-h100` |
| A100 | `google--gemma-4-31b-it-a100` |

#### Step 5: Create Online Deployment (PASS)

Deployment: `google--gemma-4-31b-it-vllm`

#### Step 6: Test Inference (FAIL)

#### Step 7: Benchmark (SKIP)


</details>


<details>
<summary><strong>2026-04-19_22-23-23</strong> — ❌ FAILED — 5/8 steps — 101m 38s</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-19_22-23-23` |
| **Status** | **FAILED** |
| **Versions** | model=6  env=6  dt=6 |
| **SKUs** | h100 a100 |
| **Total time** | 101m 38s |
| **Steps** | 5/8 passed |
| **Failed** | 5-create-online-deployment |

```bash
azureml-deployment-templates/scripts/run-e2e-cli.sh --hf-model google/gemma-4-31B-it --version 6 --tp 2 --sku Standard_NC80adis_H100_v5 --sku Standard_NC48ads_A100_v4
```

### Pipeline Steps

```
  STEP                                      TIME  STATUS    ACTION
  0-validate-model                          0m 01s  [PASS]    CREATED
  1-create-environment                     19m 35s  [PASS]    CREATED
  2-create-deployment-template              0m 11s  [PASS]    CREATED
  3-register-model                         81m 30s  [PASS]    CREATED
  4-create-online-endpoint                  0m 13s  [PASS]    CREATED
    └─ a100                                 0m 06s            CREATED
    └─ h100                                 0m 06s            CREATED
  5-create-online-deployment                0m 06s  [FAIL]  
    └─ a100                                 0m 06s            CREATED
    └─ h100                                 0m 06s            CREATED
```

#### Step 0: Validate Model (PASS)

<details>
<summary>Model Artifacts</summary>

**Total:** 11 files,  58G

| File | Size |
|------|------|
| `model-00001-of-00002.safetensors` | 46G |
| `model-00002-of-00002.safetensors` | 12G |
| `tokenizer.json` | 31M |
| `model.safetensors.index.json` | 117K |
| `README.md` | 26K |
| `chat_template.jinja` | 16K |
| `config.json` | 4.5K |
| `tokenizer_config.json` | 2.0K |
| `.gitattributes` | 1.7K |
| `processor_config.json` | 1.6K |
| `generation_config.json` | 208B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Gemma4ForConditionalGeneration` |
| **Model type** | `gemma4` |
| **Parameters** | 32.7B (32,682,372,656) |
| **Model size (weights)** | 58.25 GB (62,546,177,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 5,376 |
| **Intermediate (FFN) size** | 21,504 |
| **Num layers** | 60 |
| **Num attention heads** | 32 |
| **Num KV heads** | 16 |
| **Attention type** | Grouped-Query Attention (GQA, 2:1) |
| **Head dim** | 256 |
| **Global head dim** | 512 |
| **Vocab size** | 262,144 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `gelu_pytorch_tanh` |
| **Tie word embeddings** | True |
| **Sliding window** | 1,024 tokens |
| **Vision encoder** | 27 layers, hidden=1152, heads=16, patch=16 |

> **Weight size derivation:**
>   Parameters × 2 bytes = 65,364,745,312 bytes (60.88 GB), but `tie_word_embeddings=true` means the embedding matrix (vocab × hidden = 262,144 × 5,376 = 1,409,286,144 params, 2.62 GB) is stored once on disk instead of twice (input embed + LM head). Disk size = 65,364,745,312 − 2,818,572,288 = 62,546,173,024 bytes ≈ 62,546,177,752 bytes (58.25 GB).

##### Attention Mechanism

The model uses a **hybrid attention** pattern across 60 layers:

- **Full attention:** 10 layers — attend to all tokens in the sequence
- **Sliding window attention:** 50 layers — attend to local window of 1024 tokens

Layer pattern (S=sliding, F=full, L=linear):
```
   0:S  1:S  2:S  3:S  4:S  5:F  6:S  7:S  8:S  9:S
  10:S 11:F 12:S 13:S 14:S 15:S 16:S 17:F 18:S 19:S
  20:S 21:S 22:S 23:F 24:S 25:S 26:S 27:S 28:S 29:F
  30:S 31:S 32:S 33:S 34:S 35:F 36:S 37:S 38:S 39:S
  40:S 41:F 42:S 43:S 44:S 45:S 46:S 47:F 48:S 49:S
  50:S 51:S 52:S 53:F 54:S 55:S 56:S 57:S 58:S 59:F
```

**Pattern:** Every 6th layer is full attention (layers 5, 11, 17, 23, 29, 35, 41, 47, 53, 59)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

##### Persisted Benchmark Config

From `yaml/benchmark-config.yml` (hydrated by step 2, used by step 7):

| Setting | Value |
|---------|-------|
| Concurrencies | `[2, 4, 8, 16, 20, 30, 32]` |
| Max num seqs | `20` |

#### Step 1: Create Environment (PASS)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (PASS)

Template: `vllm-google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 3: Register Model (PASS)

Model: `google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (PASS)

| SKU | Endpoint |
|-----|----------|
| H100 | `google--gemma-4-31b-it-h100` |
| A100 | `google--gemma-4-31b-it-a100` |

#### Step 5: Create Online Deployment (FAIL)

Deployment: `google--gemma-4-31b-it-vllm`

#### Step 6: Test Inference (SKIP)

#### Step 7: Benchmark (SKIP)


</details>


<details>
<summary><strong>2026-04-19_20-24-55</strong> — ⚠️ INCOMPLETE (no summary) — ?/4 steps — unknown</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-19_20-24-55` |
| **Status** | **INCOMPLETE (no summary)** |
| **Versions** |  |
| **SKUs** |  |
| **Total time** | unknown |
| **Steps** | ?/4 passed |
| **Failed** | -- |

```bash

```

### Pipeline Steps

```

```

#### Step 0: Validate Model (RAN)

<details>
<summary>Model Artifacts</summary>

**Total:** 11 files,  58G

| File | Size |
|------|------|
| `model-00001-of-00002.safetensors` | 46G |
| `model-00002-of-00002.safetensors` | 12G |
| `tokenizer.json` | 31M |
| `model.safetensors.index.json` | 117K |
| `README.md` | 26K |
| `chat_template.jinja` | 16K |
| `config.json` | 4.5K |
| `tokenizer_config.json` | 2.0K |
| `.gitattributes` | 1.7K |
| `processor_config.json` | 1.6K |
| `generation_config.json` | 208B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Gemma4ForConditionalGeneration` |
| **Model type** | `gemma4` |
| **Parameters** | 32.7B (32,682,372,656) |
| **Model size (weights)** | 58.25 GB (62,546,177,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 5,376 |
| **Intermediate (FFN) size** | 21,504 |
| **Num layers** | 60 |
| **Num attention heads** | 32 |
| **Num KV heads** | 16 |
| **Attention type** | Grouped-Query Attention (GQA, 2:1) |
| **Head dim** | 256 |
| **Global head dim** | 512 |
| **Vocab size** | 262,144 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `gelu_pytorch_tanh` |
| **Tie word embeddings** | True |
| **Sliding window** | 1,024 tokens |
| **Vision encoder** | 27 layers, hidden=1152, heads=16, patch=16 |

> **Weight size derivation:**
>   Parameters × 2 bytes = 65,364,745,312 bytes (60.88 GB), but `tie_word_embeddings=true` means the embedding matrix (vocab × hidden = 262,144 × 5,376 = 1,409,286,144 params, 2.62 GB) is stored once on disk instead of twice (input embed + LM head). Disk size = 65,364,745,312 − 2,818,572,288 = 62,546,173,024 bytes ≈ 62,546,177,752 bytes (58.25 GB).

##### Attention Mechanism

The model uses a **hybrid attention** pattern across 60 layers:

- **Full attention:** 10 layers — attend to all tokens in the sequence
- **Sliding window attention:** 50 layers — attend to local window of 1024 tokens

Layer pattern (S=sliding, F=full, L=linear):
```
   0:S  1:S  2:S  3:S  4:S  5:F  6:S  7:S  8:S  9:S
  10:S 11:F 12:S 13:S 14:S 15:S 16:S 17:F 18:S 19:S
  20:S 21:S 22:S 23:F 24:S 25:S 26:S 27:S 28:S 29:F
  30:S 31:S 32:S 33:S 34:S 35:F 36:S 37:S 38:S 39:S
  40:S 41:F 42:S 43:S 44:S 45:S 46:S 47:F 48:S 49:S
  50:S 51:S 52:S 53:F 54:S 55:S 56:S 57:S 58:S 59:F
```

**Pattern:** Every 6th layer is full attention (layers 5, 11, 17, 23, 29, 35, 41, 47, 53, 59)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

##### Persisted Benchmark Config

From `yaml/benchmark-config.yml` (hydrated by step 2, used by step 7):

| Setting | Value |
|---------|-------|
| Concurrencies | `[2, 4, 8, 16, 20, 30, 32]` |
| Max num seqs | `20` |

#### Step 1: Create Environment (SKIP)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (SKIP)

Template: `vllm-google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 3: Register Model (SKIP)

Model: `google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (SKIP)

| SKU | Endpoint |
|-----|----------|
| H100 | `google--gemma-4-31b-it-h100` |
| A100 | `google--gemma-4-31b-it-a100` |

#### Step 5: Create Online Deployment (SKIP)

Deployment: `google--gemma-4-31b-it-vllm`

#### Step 6: Test Inference (SKIP)

#### Step 7: Benchmark (SKIP)


</details>


<details>
<summary><strong>2026-04-19_13-02-18</strong> — ⚠️ INCOMPLETE (no summary) — ?/8 steps — unknown</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-19_13-02-18` |
| **Status** | **INCOMPLETE (no summary)** |
| **Versions** |  |
| **SKUs** |  |
| **Total time** | unknown |
| **Steps** | ?/8 passed |
| **Failed** | -- |

```bash

```

### Pipeline Steps

```

```

#### Step 0: Validate Model (RAN)

<details>
<summary>Model Artifacts</summary>

**Total:** 11 files,  58G

| File | Size |
|------|------|
| `model-00001-of-00002.safetensors` | 46G |
| `model-00002-of-00002.safetensors` | 12G |
| `tokenizer.json` | 31M |
| `model.safetensors.index.json` | 117K |
| `README.md` | 26K |
| `chat_template.jinja` | 16K |
| `config.json` | 4.5K |
| `tokenizer_config.json` | 2.0K |
| `.gitattributes` | 1.7K |
| `processor_config.json` | 1.6K |
| `generation_config.json` | 208B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Gemma4ForConditionalGeneration` |
| **Model type** | `gemma4` |
| **Parameters** | 32.7B (32,682,372,656) |
| **Model size (weights)** | 58.25 GB (62,546,177,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 5,376 |
| **Intermediate (FFN) size** | 21,504 |
| **Num layers** | 60 |
| **Num attention heads** | 32 |
| **Num KV heads** | 16 |
| **Attention type** | Grouped-Query Attention (GQA, 2:1) |
| **Head dim** | 256 |
| **Global head dim** | 512 |
| **Vocab size** | 262,144 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `gelu_pytorch_tanh` |
| **Tie word embeddings** | True |
| **Sliding window** | 1,024 tokens |
| **Vision encoder** | 27 layers, hidden=1152, heads=16, patch=16 |

> **Weight size derivation:**
>   Parameters × 2 bytes = 65,364,745,312 bytes (60.88 GB), but `tie_word_embeddings=true` means the embedding matrix (vocab × hidden = 262,144 × 5,376 = 1,409,286,144 params, 2.62 GB) is stored once on disk instead of twice (input embed + LM head). Disk size = 65,364,745,312 − 2,818,572,288 = 62,546,173,024 bytes ≈ 62,546,177,752 bytes (58.25 GB).

##### Attention Mechanism

The model uses a **hybrid attention** pattern across 60 layers:

- **Full attention:** 10 layers — attend to all tokens in the sequence
- **Sliding window attention:** 50 layers — attend to local window of 1024 tokens

Layer pattern (S=sliding, F=full, L=linear):
```
   0:S  1:S  2:S  3:S  4:S  5:F  6:S  7:S  8:S  9:S
  10:S 11:F 12:S 13:S 14:S 15:S 16:S 17:F 18:S 19:S
  20:S 21:S 22:S 23:F 24:S 25:S 26:S 27:S 28:S 29:F
  30:S 31:S 32:S 33:S 34:S 35:F 36:S 37:S 38:S 39:S
  40:S 41:F 42:S 43:S 44:S 45:S 46:S 47:F 48:S 49:S
  50:S 51:S 52:S 53:F 54:S 55:S 56:S 57:S 58:S 59:F
```

**Pattern:** Every 6th layer is full attention (layers 5, 11, 17, 23, 29, 35, 41, 47, 53, 59)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

##### Persisted Benchmark Config

From `yaml/benchmark-config.yml` (hydrated by step 2, used by step 7):

| Setting | Value |
|---------|-------|
| Concurrencies | `[2, 4, 8, 16, 20, 30, 32]` |
| Max num seqs | `20` |

#### Step 1: Create Environment (SKIP)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (SKIP)

Template: `vllm-google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 3: Register Model (SKIP)

Model: `google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (SKIP)

| SKU | Endpoint |
|-----|----------|
| H100 | `google--gemma-4-31b-it-h100` |
| A100 | `google--gemma-4-31b-it-a100` |

#### Step 5: Create Online Deployment (SKIP)

Deployment: `google--gemma-4-31b-it-vllm`

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
                "content": "Here is a short introduction to Large Language Models (LLMs).\n\n### What is a Large Language Model?\nA **Large Language Model (LLM)** is a type of Artificial Intelligence trained to understand, generate, and manipulate human language. Examples include OpenAI\u2019s GPT-4, Google\u2019s Gemini, and Meta\u2019s Llama.\n\nTo understand the name, it helps to break it down:\n*   **Large:** These models are trained on massive datasets (petabytes of text from books, websites, and code) and have billions of \"parameters\"\u2014the internal variables the model adjusts to learn patterns.\n*   **Language:** Their primary purpose is to process human language, though they can also \"speak\" computer code and mathematical notation.\n*   **Model:** It is a complex mathematical algorithm (specifically a neural network) that provides a representation of how language works.\n\n### How Do They Work?\nAt their core, LLMs are **extremely advanced autocomplete systems.** \n\nThey do not \"know\" facts in the way humans do; instead, they use **probability**. When you give an LLM a prompt, it analyzes the sequence of words and predicts what the most likely next \"token\" (a chunk of a word) should be based on the patterns it saw during training. \n\nMost modern LLMs use an architecture called the **Transformer**, which allows the model to use a mechanism called \"attention.\" This enables the AI to understand the relationship between words even if they are far apart in a sentence, allowing it to grasp context and nuance.\n\n### What Can They Do?\nBecause they have internalized the patterns of human communication, LLMs are incredibly versatile:\n*   **Content Generation:** Writing emails, essays, poems, or scripts.\n*   **Summarization:** Condensing long documents into key bullet points.\n*   **Translation:** Converting one language to another with high fluency.\n*   **Coding:** Writing and debugging software in various programming languages.\n*   **Reasoning:** Solving logic puzzles or explaining complex scientific concepts.\n\n### Key Limitations\nDespite their power, LLMs have notable weaknesses:\n1.  **Hallucination:** Because they predict the *most likely* next word rather than searching a database of facts, they can confidently state things that are completely false.\n2.  **Lack of True Consciousness:** They do not have beliefs, feelings, or a physical understanding of the world; they are simulating intelligence through pattern recognition.\n3",
                "refusal": null,
                "annotations": null,
                "audio": null,
                "function_call": null,
                "tool_calls": [],
                "reasoning": null
            },
            "logprobs": null,
            "finish_reason": "length",
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
                "content": "Here is a short introduction to Large Language Models (LLMs).\n\n### What is a Large Language Model?\nA **Large Language Model (LLM)** is a type of Artificial Intelligence trained to understand, generate, and manipulate human language. Examples include OpenAI\u2019s GPT-4, Google\u2019s Gemini, and Meta\u2019s Llama.\n\nTo understand the name, it helps to break it down:\n*   **Large:** These models are trained on massive datasets (petabytes of text from books, websites, and code) and have billions of \"parameters\"\u2014the internal variables the model adjusts to learn patterns.\n*   **Language:** Their primary purpose is to process human language, though they can also \"speak\" computer code and mathematical notation.\n*   **Model:** It is a complex mathematical algorithm (specifically a neural network) that provides a representation of how language works.\n\n### How Do They Work?\nAt their core, LLMs are **extremely advanced autocomplete systems.** They do not \"know\" facts in the way humans do; instead, they use probability.\n\n1.  **Tokenization:** The model breaks text down into smaller chunks called \"tokens\" (which can be words or parts of words).\n2.  **Pattern Recognition:** During training, the model analyzes billions of sentences to learn which tokens typically follow others. For example, if it sees the phrase *\"The capital of France is...\"*, it has learned that the most statistically likely next token is *\"Paris.\"*\n3.  **The Transformer Architecture:** Most modern LLMs use a technology called a **Transformer**. This allows the model to use \"attention,\" meaning it can look at all the words in a sentence simultaneously to understand context. (For instance, it can tell if the word \"bank\" refers to a riverbank or a financial institution based on the surrounding words).\n\n### What Can They Do?\nBecause they understand the structure of language, LLMs are incredibly versatile:\n*   **Content Creation:** Writing emails, essays, poems, or scripts.\n*   **Summarization:** Condensing long documents into key bullet points.\n*   **Translation:** Converting one language to another with high fluency.\n*   **Coding:** Writing and debugging software in various programming languages.\n*   **Reasoning:** Solving logic puzzles or explaining complex scientific concepts.\n\n### Key Limitations\nDespite their power, LLMs have important drawbacks:\n*   **Hallucinations:** Because they predict the *most likely",
                "refusal": null,
                "annotations": null,
                "audio": null,
                "function_call": null,
                "tool_calls": [],
                "reasoning": null
            },
            "logprobs": null,
            "finish_reason": "length",
```

</details>

#### Step 7: Benchmark (SKIP)

##### H100

- **Benchmark runs:** 25
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 2003.2ms | ITL(avg): 27.3ms

##### A100

- **Benchmark runs:** 13
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 301.1ms | ITL(avg): 44.4ms

##### Benchmark Plots

###### Benchmark Avg

![Benchmark Avg](logs/e2e/2026-04-19_13-02-18/benchmark/plots/benchmark_avg.png)

###### Benchmark P50

![Benchmark P50](logs/e2e/2026-04-19_13-02-18/benchmark/plots/benchmark_p50.png)

###### Benchmark P90

![Benchmark P90](logs/e2e/2026-04-19_13-02-18/benchmark/plots/benchmark_p90.png)

###### Errors

![Errors](logs/e2e/2026-04-19_13-02-18/benchmark/plots/errors.png)

<details>
<summary>Percentile breakdown by token shape</summary>

###### Percentiles Long Gen

![Percentiles Long Gen](logs/e2e/2026-04-19_13-02-18/benchmark/plots/percentiles_long_gen.png)

###### Percentiles Long Prompt

![Percentiles Long Prompt](logs/e2e/2026-04-19_13-02-18/benchmark/plots/percentiles_long_prompt.png)

###### Percentiles Short Gen

![Percentiles Short Gen](logs/e2e/2026-04-19_13-02-18/benchmark/plots/percentiles_short_gen.png)

###### Percentiles Short Prompt

![Percentiles Short Prompt](logs/e2e/2026-04-19_13-02-18/benchmark/plots/percentiles_short_prompt.png)

</details>

</details>


<details>
<summary><strong>2026-04-19_13-01-23</strong> — ❌ FAILED — 2/8 steps — 0m 14s</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-19_13-01-23` |
| **Status** | **FAILED** |
| **Versions** | model=2  env=2  dt=3 |
| **SKUs** | h100 a100 |
| **Total time** | 0m 14s |
| **Steps** | 2/8 passed |
| **Failed** | 2-create-deployment-template |

```bash
azureml-deployment-templates/scripts/run-e2e-cli.sh --hf-model google/gemma-4-31B-it --dt-version 3 --env-version 2 --model-version 2 --sku Standard_NC80adis_H100_v5 --sku Standard_NC48ads_A100_v4
```

### Pipeline Steps

```
  STEP                                      TIME  STATUS    ACTION
  0-validate-model                          0m 01s  [PASS]    CREATED
  1-create-environment                      0m 13s  [PASS]    CREATED
  2-create-deployment-template              0m 00s  [FAIL]  
```

#### Step 0: Validate Model (PASS)

<details>
<summary>Model Artifacts</summary>

**Total:** 11 files,  58G

| File | Size |
|------|------|
| `model-00001-of-00002.safetensors` | 46G |
| `model-00002-of-00002.safetensors` | 12G |
| `tokenizer.json` | 31M |
| `model.safetensors.index.json` | 117K |
| `README.md` | 26K |
| `chat_template.jinja` | 16K |
| `config.json` | 4.5K |
| `tokenizer_config.json` | 2.0K |
| `.gitattributes` | 1.7K |
| `processor_config.json` | 1.6K |
| `generation_config.json` | 208B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Gemma4ForConditionalGeneration` |
| **Model type** | `gemma4` |
| **Parameters** | 32.7B (32,682,372,656) |
| **Model size (weights)** | 58.25 GB (62,546,177,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 5,376 |
| **Intermediate (FFN) size** | 21,504 |
| **Num layers** | 60 |
| **Num attention heads** | 32 |
| **Num KV heads** | 16 |
| **Attention type** | Grouped-Query Attention (GQA, 2:1) |
| **Head dim** | 256 |
| **Global head dim** | 512 |
| **Vocab size** | 262,144 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `gelu_pytorch_tanh` |
| **Tie word embeddings** | True |
| **Sliding window** | 1,024 tokens |
| **Vision encoder** | 27 layers, hidden=1152, heads=16, patch=16 |

> **Weight size derivation:**
>   Parameters × 2 bytes = 65,364,745,312 bytes (60.88 GB), but `tie_word_embeddings=true` means the embedding matrix (vocab × hidden = 262,144 × 5,376 = 1,409,286,144 params, 2.62 GB) is stored once on disk instead of twice (input embed + LM head). Disk size = 65,364,745,312 − 2,818,572,288 = 62,546,173,024 bytes ≈ 62,546,177,752 bytes (58.25 GB).

##### Attention Mechanism

The model uses a **hybrid attention** pattern across 60 layers:

- **Full attention:** 10 layers — attend to all tokens in the sequence
- **Sliding window attention:** 50 layers — attend to local window of 1024 tokens

Layer pattern (S=sliding, F=full, L=linear):
```
   0:S  1:S  2:S  3:S  4:S  5:F  6:S  7:S  8:S  9:S
  10:S 11:F 12:S 13:S 14:S 15:S 16:S 17:F 18:S 19:S
  20:S 21:S 22:S 23:F 24:S 25:S 26:S 27:S 28:S 29:F
  30:S 31:S 32:S 33:S 34:S 35:F 36:S 37:S 38:S 39:S
  40:S 41:F 42:S 43:S 44:S 45:S 46:S 47:F 48:S 49:S
  50:S 51:S 52:S 53:F 54:S 55:S 56:S 57:S 58:S 59:F
```

**Pattern:** Every 6th layer is full attention (layers 5, 11, 17, 23, 29, 35, 41, 47, 53, 59)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

##### Persisted Benchmark Config

From `yaml/benchmark-config.yml` (hydrated by step 2, used by step 7):

| Setting | Value |
|---------|-------|
| Concurrencies | `[2, 4, 8, 16, 20, 30, 32]` |
| Max num seqs | `20` |

#### Step 1: Create Environment (PASS)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (FAIL)

Template: `vllm-google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 3: Register Model (SKIP)

Model: `google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (SKIP)

| SKU | Endpoint |
|-----|----------|
| H100 | `google--gemma-4-31b-it-h100` |
| A100 | `google--gemma-4-31b-it-a100` |

#### Step 5: Create Online Deployment (SKIP)

Deployment: `google--gemma-4-31b-it-vllm`

#### Step 6: Test Inference (SKIP)

#### Step 7: Benchmark (SKIP)


</details>


<details>
<summary><strong>2026-04-19_12-33-14</strong> — ✅ PASSED — 8/8 steps — 13m 0s</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-19_12-33-14` |
| **Status** | **PASSED** |
| **Versions** | model=2  env=2  dt=3 |
| **SKUs** | h100 a100 |
| **Total time** | 13m 0s |
| **Steps** | 8/8 passed |
| **Failed** | -- |

```bash
azureml-deployment-templates/scripts/run-e2e-cli.sh --hf-model google/gemma-4-31B-it --dt-version 3 --env-version 2 --model-version 2 --sku Standard_NC80adis_H100_v5 --sku Standard_NC48ads_A100_v4
```

### Pipeline Steps

```
  STEP                                      TIME  STATUS    ACTION
  0-validate-model                          0m 01s  [PASS]    CREATED
  1-create-environment                      0m 12s  [PASS]    CREATED
  2-create-deployment-template              0m 07s  [PASS]    CREATED
  3-register-model                          0m 12s  [PASS]    CREATED
  4-create-online-endpoint                  0m 13s  [PASS]    CREATED
    └─ a100                                 0m 04s            CREATED
    └─ h100                                 0m 03s            CREATED
  5-create-online-deployment                0m 09s  [PASS]    CREATED
    └─ a100                                 0m 03s            CREATED
    └─ h100                                 0m 03s            CREATED
  6-test-inference                          0m 47s  [PASS]    CREATED
    └─ a100                                 0m 29s            CREATED
    └─ h100                                 0m 17s            CREATED
  7-benchmark                              11m 18s  [PASS]    CREATED
    └─ a100                                10m 54s            CREATED
    └─ h100                                10m 54s            CREATED
```

#### Step 0: Validate Model (PASS)

<details>
<summary>Model Artifacts</summary>

**Total:** 11 files,  58G

| File | Size |
|------|------|
| `model-00001-of-00002.safetensors` | 46G |
| `model-00002-of-00002.safetensors` | 12G |
| `tokenizer.json` | 31M |
| `model.safetensors.index.json` | 117K |
| `README.md` | 26K |
| `chat_template.jinja` | 16K |
| `config.json` | 4.5K |
| `tokenizer_config.json` | 2.0K |
| `.gitattributes` | 1.7K |
| `processor_config.json` | 1.6K |
| `generation_config.json` | 208B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Gemma4ForConditionalGeneration` |
| **Model type** | `gemma4` |
| **Parameters** | 32.7B (32,682,372,656) |
| **Model size (weights)** | 58.25 GB (62,546,177,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 5,376 |
| **Intermediate (FFN) size** | 21,504 |
| **Num layers** | 60 |
| **Num attention heads** | 32 |
| **Num KV heads** | 16 |
| **Attention type** | Grouped-Query Attention (GQA, 2:1) |
| **Head dim** | 256 |
| **Global head dim** | 512 |
| **Vocab size** | 262,144 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `gelu_pytorch_tanh` |
| **Tie word embeddings** | True |
| **Sliding window** | 1,024 tokens |
| **Vision encoder** | 27 layers, hidden=1152, heads=16, patch=16 |

> **Weight size derivation:**
>   Parameters × 2 bytes = 65,364,745,312 bytes (60.88 GB), but `tie_word_embeddings=true` means the embedding matrix (vocab × hidden = 262,144 × 5,376 = 1,409,286,144 params, 2.62 GB) is stored once on disk instead of twice (input embed + LM head). Disk size = 65,364,745,312 − 2,818,572,288 = 62,546,173,024 bytes ≈ 62,546,177,752 bytes (58.25 GB).

##### Attention Mechanism

The model uses a **hybrid attention** pattern across 60 layers:

- **Full attention:** 10 layers — attend to all tokens in the sequence
- **Sliding window attention:** 50 layers — attend to local window of 1024 tokens

Layer pattern (S=sliding, F=full, L=linear):
```
   0:S  1:S  2:S  3:S  4:S  5:F  6:S  7:S  8:S  9:S
  10:S 11:F 12:S 13:S 14:S 15:S 16:S 17:F 18:S 19:S
  20:S 21:S 22:S 23:F 24:S 25:S 26:S 27:S 28:S 29:F
  30:S 31:S 32:S 33:S 34:S 35:F 36:S 37:S 38:S 39:S
  40:S 41:F 42:S 43:S 44:S 45:S 46:S 47:F 48:S 49:S
  50:S 51:S 52:S 53:F 54:S 55:S 56:S 57:S 58:S 59:F
```

**Pattern:** Every 6th layer is full attention (layers 5, 11, 17, 23, 29, 35, 41, 47, 53, 59)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

##### Persisted Benchmark Config

From `yaml/benchmark-config.yml` (hydrated by step 2, used by step 7):

| Setting | Value |
|---------|-------|
| Concurrencies | `[2, 4, 8, 16, 20, 30, 32]` |
| Max num seqs | `20` |

#### Step 1: Create Environment (PASS)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (PASS)

Template: `vllm-google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 3: Register Model (PASS)

Model: `google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (PASS)

| SKU | Endpoint |
|-----|----------|
| H100 | `google--gemma-4-31b-it-h100` |
| A100 | `google--gemma-4-31b-it-a100` |

#### Step 5: Create Online Deployment (PASS)

Deployment: `google--gemma-4-31b-it-vllm`

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
                "content": "At its simplest, a **Large Language Model (LLM)** is a type of Artificial Intelligence trained to understand, generate, and manipulate human language. If you have used ChatGPT, Claude, or Gemini, you have interacted with an LLM.\n\nHere is a short breakdown of how they work and what makes them \"large.\"\n\n### 1. How they work: The \"Prediction Engine\"\nContrary to how they feel, LLMs do not \"think\" or \"know\" facts in the way humans do. Instead, they are incredibly sophisticated **statistical prediction engines**.\n\nDuring training, an LLM reads massive amounts of text (books, websites, articles, code). It learns the patterns of how words relate to one another. When you give it a prompt, the model isn't looking up an answer in a database; it is calculating the **probability** of which token (a chunk of a word) should come next based on the sequence that came before it.\n\n### 2. What makes them \"Large\"?\nThe \"Large\" in LLM refers to two things:\n*   **The Training Data:** They are trained on petabytes of text, encompassing nearly the entirety of the public internet and digitized libraries.\n*   **The Parameters:** Parameters are the internal \"dials\" or connections the model adjusts during learning to understand nuances. Modern LLMs have billions (and sometimes trillions) of these parameters, allowing them to capture complex grammar, reasoning patterns, and even different languages.\n\n### 3. The Secret Sauce: The Transformer\nAlmost all modern LLMs use an architecture called the **Transformer**, introduced by Google researchers in 2017. The key innovation of the Transformer is **\"Attention.\"** \n\nAttention allows the model to look at every word in a sentence simultaneously to determine which ones are most important. For example, in the sentence *\"The bank of the river was muddy,\"* the word \"river\" tells the model that \"bank\" refers to land, not a financial institution.\n\n### 4. What can they do?\nBecause they have learned the general patterns of human communication, LLMs are versatile. They can:\n*   **Generate:** Write emails, essays, or poems.\n*   **Summarize:** Condense a long article into three bullet points.\n*   **Translate:** Convert one language to another.\n*   **Code:** Write and debug programming languages.\n\n### 5. The Main Limitation: Hallucinations\n",
                "refusal": null,
                "annotations": null,
                "audio": null,
                "function_call": null,
                "tool_calls": [],
                "reasoning": null
            },
            "logprobs": null,
            "finish_reason": "length",
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
                "content": "At its simplest, a **Large Language Model (LLM)** is a type of Artificial Intelligence trained to understand, generate, and manipulate human language. If you have used ChatGPT, Claude, or Gemini, you have interacted with an LLM.\n\nHere is a breakdown of what they are and how they work:\n\n### 1. What does the name mean?\n*   **Large:** These models are \"large\" in two ways. First, they are trained on massive datasets (petabytes of text from books, websites, and code). Second, they have billions of **parameters**, which are the internal \"switches\" the model adjusts during learning to recognize patterns.\n*   **Language:** Their primary purpose is to process human language, though they can also \"speak\" computer code and mathematical notation.\n*   **Model:** It is a mathematical representation (an algorithm) of how language works, rather than a database of facts.\n\n### 2. How do they actually work?\nContrary to how it feels, an LLM isn't \"thinking\" or \"reasoning\" like a human. Instead, it is performing high-level **statistical prediction**.\n\nImagine the \"autofill\" feature on your smartphone, but scaled up by a billion. An LLM predicts the **next token** (a chunk of a word) in a sequence based on the context of the words that came before it. Because it has seen almost every combination of words on the internet, it can predict the next word so accurately that it creates coherent essays, poems, or computer programs.\n\n### 3. The Secret Sauce: The Transformer\nThe technology that made LLMs possible is called the **Transformer architecture** (introduced by Google in 2017). Its key innovation is **\"Attention.\"**\n\n\"Attention\" allows the model to look at a whole sentence at once and figure out which words are most important to one another. For example, in the sentence *\"The bank of the river was muddy,\"* the model uses attention to link the word \"bank\" to \"river,\" knowing it refers to land, not a financial institution.\n\n### 4. What can they do?\nBecause they are general-purpose, LLMs can perform a vast array of tasks without being specifically programmed for each one:\n*   **Generation:** Writing emails, stories, or code.\n*   **Summarization:** Condensing a long article into three bullet points.\n*   **Translation:** Converting",
                "refusal": null,
                "annotations": null,
                "audio": null,
                "function_call": null,
                "tool_calls": [],
                "reasoning": null
            },
            "logprobs": null,
            "finish_reason": "length",
```

</details>

#### Step 7: Benchmark (PASS)

##### H100

- **Benchmark runs:** 28
- **Total errors:** 0
- **Sample metrics (c=2):** no metrics

##### A100

- **Benchmark runs:** 28
- **Total errors:** 0
- **Sample metrics (c=2):** no metrics

##### Benchmark Plots

###### Benchmark Avg

![Benchmark Avg](logs/e2e/2026-04-19_12-33-14/benchmark/plots/benchmark_avg.png)

###### Benchmark P50

![Benchmark P50](logs/e2e/2026-04-19_12-33-14/benchmark/plots/benchmark_p50.png)

###### Benchmark P90

![Benchmark P90](logs/e2e/2026-04-19_12-33-14/benchmark/plots/benchmark_p90.png)

<details>
<summary>Percentile breakdown by token shape</summary>

###### Percentiles Long Gen

![Percentiles Long Gen](logs/e2e/2026-04-19_12-33-14/benchmark/plots/percentiles_long_gen.png)

###### Percentiles Long Prompt

![Percentiles Long Prompt](logs/e2e/2026-04-19_12-33-14/benchmark/plots/percentiles_long_prompt.png)

###### Percentiles Short Gen

![Percentiles Short Gen](logs/e2e/2026-04-19_12-33-14/benchmark/plots/percentiles_short_gen.png)

###### Percentiles Short Prompt

![Percentiles Short Prompt](logs/e2e/2026-04-19_12-33-14/benchmark/plots/percentiles_short_prompt.png)

</details>

</details>


<details>
<summary><strong>2026-04-19_12-27-26</strong> — ❌ FAILED — 3/8 steps — 0m 34s</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-19_12-27-26` |
| **Status** | **FAILED** |
| **Versions** | model=2  env=2  dt=3 |
| **SKUs** | h100 a100 |
| **Total time** | 0m 34s |
| **Steps** | 3/8 passed |
| **Failed** | 3-register-model |

```bash
azureml-deployment-templates/scripts/run-e2e-cli.sh --hf-model google/gemma-4-31B-it --dt-version 3 --env-version 2 --model-version 2 --sku Standard_NC80adis_H100_v5 --sku Standard_NC48ads_A100_v4
```

### Pipeline Steps

```
  STEP                                      TIME  STATUS    ACTION
  0-validate-model                          0m 01s  [PASS]    CREATED
  1-create-environment                      0m 14s  [PASS]    CREATED
  2-create-deployment-template              0m 11s  [PASS]    CREATED
  3-register-model                          0m 08s  [FAIL]  
```

#### Step 0: Validate Model (PASS)

<details>
<summary>Model Artifacts</summary>

**Total:** 11 files,  58G

| File | Size |
|------|------|
| `model-00001-of-00002.safetensors` | 46G |
| `model-00002-of-00002.safetensors` | 12G |
| `tokenizer.json` | 31M |
| `model.safetensors.index.json` | 117K |
| `README.md` | 26K |
| `chat_template.jinja` | 16K |
| `config.json` | 4.5K |
| `tokenizer_config.json` | 2.0K |
| `.gitattributes` | 1.7K |
| `processor_config.json` | 1.6K |
| `generation_config.json` | 208B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Gemma4ForConditionalGeneration` |
| **Model type** | `gemma4` |
| **Parameters** | 32.7B (32,682,372,656) |
| **Model size (weights)** | 58.25 GB (62,546,177,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 5,376 |
| **Intermediate (FFN) size** | 21,504 |
| **Num layers** | 60 |
| **Num attention heads** | 32 |
| **Num KV heads** | 16 |
| **Attention type** | Grouped-Query Attention (GQA, 2:1) |
| **Head dim** | 256 |
| **Global head dim** | 512 |
| **Vocab size** | 262,144 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `gelu_pytorch_tanh` |
| **Tie word embeddings** | True |
| **Sliding window** | 1,024 tokens |
| **Vision encoder** | 27 layers, hidden=1152, heads=16, patch=16 |

> **Weight size derivation:**
>   Parameters × 2 bytes = 65,364,745,312 bytes (60.88 GB), but `tie_word_embeddings=true` means the embedding matrix (vocab × hidden = 262,144 × 5,376 = 1,409,286,144 params, 2.62 GB) is stored once on disk instead of twice (input embed + LM head). Disk size = 65,364,745,312 − 2,818,572,288 = 62,546,173,024 bytes ≈ 62,546,177,752 bytes (58.25 GB).

##### Attention Mechanism

The model uses a **hybrid attention** pattern across 60 layers:

- **Full attention:** 10 layers — attend to all tokens in the sequence
- **Sliding window attention:** 50 layers — attend to local window of 1024 tokens

Layer pattern (S=sliding, F=full, L=linear):
```
   0:S  1:S  2:S  3:S  4:S  5:F  6:S  7:S  8:S  9:S
  10:S 11:F 12:S 13:S 14:S 15:S 16:S 17:F 18:S 19:S
  20:S 21:S 22:S 23:F 24:S 25:S 26:S 27:S 28:S 29:F
  30:S 31:S 32:S 33:S 34:S 35:F 36:S 37:S 38:S 39:S
  40:S 41:F 42:S 43:S 44:S 45:S 46:S 47:F 48:S 49:S
  50:S 51:S 52:S 53:F 54:S 55:S 56:S 57:S 58:S 59:F
```

**Pattern:** Every 6th layer is full attention (layers 5, 11, 17, 23, 29, 35, 41, 47, 53, 59)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

##### Persisted Benchmark Config

From `yaml/benchmark-config.yml` (hydrated by step 2, used by step 7):

| Setting | Value |
|---------|-------|
| Concurrencies | `[2, 4, 8, 16, 20, 30, 32]` |
| Max num seqs | `20` |

#### Step 1: Create Environment (PASS)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (PASS)

Template: `vllm-google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 3: Register Model (FAIL)

Model: `google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (SKIP)

| SKU | Endpoint |
|-----|----------|
| H100 | `google--gemma-4-31b-it-h100` |
| A100 | `google--gemma-4-31b-it-a100` |

#### Step 5: Create Online Deployment (SKIP)

Deployment: `google--gemma-4-31b-it-vllm`

#### Step 6: Test Inference (SKIP)

#### Step 7: Benchmark (SKIP)


</details>


<details>
<summary><strong>2026-04-19_00-42-32</strong> — ✅ PASSED — 8/8 steps — 631m 3s</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-19_00-42-32` |
| **Status** | **PASSED** |
| **Versions** | model=2  env=2  dt=2 |
| **SKUs** | h100 a100 |
| **Total time** | 631m 3s |
| **Steps** | 8/8 passed |
| **Failed** | -- |

```bash
azureml-deployment-templates/scripts/run-e2e-cli.sh --hf-model google/gemma-4-31B-it --version 2 --sku Standard_NC80adis_H100_v5 --sku Standard_NC48ads_A100_v4
```

### Pipeline Steps

```
  STEP                                      TIME  STATUS    ACTION
  0-validate-model                          0m 01s  [PASS]    CREATED
  1-create-environment                      1m 27s  [PASS]    CREATED
  2-create-deployment-template              0m 11s  [PASS]    CREATED
  3-register-model                         79m 44s  [PASS]    CREATED
  4-create-online-endpoint                  0m 09s  [PASS]    CREATED
    └─ a100                                 0m 02s            CREATED
    └─ h100                                 0m 02s            CREATED
  5-create-online-deployment               31m 15s  [PASS]    CREATED
    └─ a100                                30m 40s            CREATED
    └─ h100                                31m 10s            CREATED
  6-test-inference                          0m 51s  [PASS]    CREATED
    └─ a100                                 0m 31s            CREATED
    └─ h100                                 0m 19s            CREATED
  7-benchmark                             517m 25s  [PASS]    CREATED
    └─ a100                               506m 11s            CREATED
    └─ h100                               517m 01s            CREATED
```

#### Step 0: Validate Model (PASS)

<details>
<summary>Model Artifacts</summary>

**Total:** 11 files,  58G

| File | Size |
|------|------|
| `model-00001-of-00002.safetensors` | 46G |
| `model-00002-of-00002.safetensors` | 12G |
| `tokenizer.json` | 31M |
| `model.safetensors.index.json` | 117K |
| `README.md` | 26K |
| `chat_template.jinja` | 16K |
| `config.json` | 4.5K |
| `tokenizer_config.json` | 2.0K |
| `.gitattributes` | 1.7K |
| `processor_config.json` | 1.6K |
| `generation_config.json` | 208B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Gemma4ForConditionalGeneration` |
| **Model type** | `gemma4` |
| **Parameters** | 32.7B (32,682,372,656) |
| **Model size (weights)** | 58.25 GB (62,546,177,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 5,376 |
| **Intermediate (FFN) size** | 21,504 |
| **Num layers** | 60 |
| **Num attention heads** | 32 |
| **Num KV heads** | 16 |
| **Attention type** | Grouped-Query Attention (GQA, 2:1) |
| **Head dim** | 256 |
| **Global head dim** | 512 |
| **Vocab size** | 262,144 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `gelu_pytorch_tanh` |
| **Tie word embeddings** | True |
| **Sliding window** | 1,024 tokens |
| **Vision encoder** | 27 layers, hidden=1152, heads=16, patch=16 |

> **Weight size derivation:**
>   Parameters × 2 bytes = 65,364,745,312 bytes (60.88 GB), but `tie_word_embeddings=true` means the embedding matrix (vocab × hidden = 262,144 × 5,376 = 1,409,286,144 params, 2.62 GB) is stored once on disk instead of twice (input embed + LM head). Disk size = 65,364,745,312 − 2,818,572,288 = 62,546,173,024 bytes ≈ 62,546,177,752 bytes (58.25 GB).

##### Attention Mechanism

The model uses a **hybrid attention** pattern across 60 layers:

- **Full attention:** 10 layers — attend to all tokens in the sequence
- **Sliding window attention:** 50 layers — attend to local window of 1024 tokens

Layer pattern (S=sliding, F=full, L=linear):
```
   0:S  1:S  2:S  3:S  4:S  5:F  6:S  7:S  8:S  9:S
  10:S 11:F 12:S 13:S 14:S 15:S 16:S 17:F 18:S 19:S
  20:S 21:S 22:S 23:F 24:S 25:S 26:S 27:S 28:S 29:F
  30:S 31:S 32:S 33:S 34:S 35:F 36:S 37:S 38:S 39:S
  40:S 41:F 42:S 43:S 44:S 45:S 46:S 47:F 48:S 49:S
  50:S 51:S 52:S 53:F 54:S 55:S 56:S 57:S 58:S 59:F
```

**Pattern:** Every 6th layer is full attention (layers 5, 11, 17, 23, 29, 35, 41, 47, 53, 59)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

##### Persisted Benchmark Config

From `yaml/benchmark-config.yml` (hydrated by step 2, used by step 7):

| Setting | Value |
|---------|-------|
| Concurrencies | `[2, 4, 8, 16, 20, 30, 32]` |
| Max num seqs | `20` |

#### Step 1: Create Environment (PASS)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (PASS)

Template: `vllm-google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 3: Register Model (PASS)

Model: `google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (PASS)

| SKU | Endpoint |
|-----|----------|
| H100 | `google--gemma-4-31b-it-h100` |
| A100 | `google--gemma-4-31b-it-a100` |

#### Step 5: Create Online Deployment (PASS)

Deployment: `google--gemma-4-31b-it-vllm`

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
                "content": "Here is a short introduction to Large Language Models (LLMs).\n\n### What is a Large Language Model?\nA **Large Language Model (LLM)** is a type of Artificial Intelligence trained to understand, generate, and manipulate human language. Examples include OpenAI\u2019s GPT-4, Google\u2019s Gemini, and Meta\u2019s Llama.\n\nTo understand the name, it helps to break it down:\n*   **Large:** These models are trained on massive datasets (petabytes of text from books, websites, and code) and have billions of \"parameters\"\u2014the internal variables the model adjusts to learn patterns.\n*   **Language:** Their primary purpose is to process human language, though they can also \"speak\" computer code and mathematical notation.\n*   **Model:** It is a complex mathematical algorithm (specifically a neural network) that provides a representation of how language works.\n\n### How Do They Work?\nAt their core, LLMs are **extremely advanced autocomplete systems.** \n\nThey do not \"know\" facts in the way humans do; instead, they use **probability**. When you give an LLM a prompt, it analyzes the sequence of words and predicts what the most likely next \"token\" (a chunk of a word) should be based on the patterns it saw during training. \n\nMost modern LLMs use an architecture called the **Transformer**, which allows the model to use a mechanism called \"attention.\" This enables the AI to understand the relationship between words even if they are far apart in a sentence, allowing it to grasp context and nuance.\n\n### What Can They Do?\nBecause they have internalized the patterns of human communication, LLMs are incredibly versatile:\n*   **Content Generation:** Writing emails, essays, poems, or scripts.\n*   **Summarization:** Condensing long documents into key bullet points.\n*   **Translation:** Converting one language to another with high fluency.\n*   **Coding:** Writing and debugging software in various programming languages.\n*   **Reasoning:** Solving logic puzzles or explaining complex scientific concepts.\n\n### Key Limitations\nDespite their power, LLMs have notable weaknesses:\n1.  **Hallucination:** Because they predict the *most likely* next word rather than searching a database of facts, they can confidently state things that are completely false.\n2.  **Lack of True Consciousness:** They do not have beliefs, feelings, or a physical understanding of the world; they are simulating intelligence through pattern recognition.\n3",
                "refusal": null,
                "annotations": null,
                "audio": null,
                "function_call": null,
                "tool_calls": [],
                "reasoning": null
            },
            "logprobs": null,
            "finish_reason": "length",
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
                "content": "Here is a short introduction to Large Language Models (LLMs).\n\n### What is a Large Language Model?\nA **Large Language Model (LLM)** is a type of Artificial Intelligence trained to understand, generate, and manipulate human language. Examples include OpenAI\u2019s GPT-4, Google\u2019s Gemini, and Meta\u2019s Llama.\n\nTo understand the name, it helps to break it down:\n*   **Large:** These models are trained on massive datasets (petabytes of text from books, websites, and code) and have billions of \"parameters\"\u2014the internal variables the model adjusts to learn patterns.\n*   **Language:** Their primary purpose is to process human language, though they can also \"speak\" computer code and mathematical notation.\n*   **Model:** It is a complex mathematical algorithm (specifically a neural network) that provides a representation of how language works.\n\n### How Do They Work?\nAt their core, LLMs are **extremely advanced autocomplete systems.** They do not \"know\" facts in the way humans do; instead, they use probability.\n\n1.  **Tokenization:** The model breaks text down into smaller chunks called \"tokens\" (which can be words or parts of words).\n2.  **Pattern Recognition:** During training, the model analyzes billions of sentences to learn which tokens typically follow others. For example, if it sees the phrase *\"The capital of France is...\"*, it has learned that the most statistically likely next token is *\"Paris.\"*\n3.  **The Transformer Architecture:** Most modern LLMs use a technology called a **Transformer**. This allows the model to use \"attention,\" meaning it can look at all the words in a sentence simultaneously to understand context. (For instance, it can tell if the word \"bank\" refers to a riverbank or a financial institution based on the surrounding words).\n\n### What Can They Do?\nBecause they understand the structure of language, LLMs are incredibly versatile:\n*   **Content Creation:** Writing emails, essays, poems, or scripts.\n*   **Summarization:** Condensing long documents into key bullet points.\n*   **Translation:** Converting one language to another with high fluency.\n*   **Coding:** Writing and debugging software in various programming languages.\n*   **Reasoning:** Solving logic puzzles or explaining complex scientific concepts.\n\n### Key Limitations\nDespite their power, LLMs have important drawbacks:\n*   **Hallucinations:** Because they predict the *most likely",
                "refusal": null,
                "annotations": null,
                "audio": null,
                "function_call": null,
                "tool_calls": [],
                "reasoning": null
            },
            "logprobs": null,
            "finish_reason": "length",
```

</details>

#### Step 7: Benchmark (PASS)

##### H100

- **Benchmark runs:** 28
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 2028.1ms | ITL(avg): 27.7ms

##### A100

- **Benchmark runs:** 28
- **Total errors:** 0
- **Sample metrics (c=2):** TTFT(avg): 3730.7ms | ITL(avg): 51.7ms

##### Benchmark Plots

###### Benchmark Avg

![Benchmark Avg](logs/e2e/2026-04-19_00-42-32/benchmark/plots/benchmark_avg.png)

###### Benchmark P50

![Benchmark P50](logs/e2e/2026-04-19_00-42-32/benchmark/plots/benchmark_p50.png)

###### Benchmark P90

![Benchmark P90](logs/e2e/2026-04-19_00-42-32/benchmark/plots/benchmark_p90.png)

<details>
<summary>Percentile breakdown by token shape</summary>

###### Percentiles Long Gen

![Percentiles Long Gen](logs/e2e/2026-04-19_00-42-32/benchmark/plots/percentiles_long_gen.png)

###### Percentiles Long Prompt

![Percentiles Long Prompt](logs/e2e/2026-04-19_00-42-32/benchmark/plots/percentiles_long_prompt.png)

###### Percentiles Short Gen

![Percentiles Short Gen](logs/e2e/2026-04-19_00-42-32/benchmark/plots/percentiles_short_gen.png)

###### Percentiles Short Prompt

![Percentiles Short Prompt](logs/e2e/2026-04-19_00-42-32/benchmark/plots/percentiles_short_prompt.png)

</details>

</details>


<details>
<summary><strong>2026-04-19_00-02-44</strong> — ❌ FAILED — 5/8 steps — 35m 12s</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | `2026-04-19_00-02-44` |
| **Status** | **FAILED** |
| **Versions** | model=1  env=1  dt=1 |
| **SKUs** | h100 a100 |
| **Total time** | 35m 12s |
| **Steps** | 5/8 passed |
| **Failed** | 5-create-online-deployment |

```bash
azureml-deployment-templates/scripts/run-e2e-cli.sh --hf-model google/gemma-4-31B-it --version 1 --sku Standard_NC80adis_H100_v5 --sku Standard_NC48ads_A100_v4
```

### Pipeline Steps

```
  STEP                                      TIME  STATUS    ACTION
  0-validate-model                         10m 53s  [PASS]    CREATED
  1-create-environment                      0m 27s  [PASS]    CREATED
  2-create-deployment-template              2m 14s  [PASS]    CREATED
  3-register-model                          0m 09s  [PASS]    CREATED
  4-create-online-endpoint                  1m 17s  [PASS]    CREATED
    └─ a100                                 1m 10s            CREATED
    └─ h100                                 1m 10s            CREATED
  5-create-online-deployment               20m 12s  [FAIL]  
    └─ a100                                20m 11s            CREATED
    └─ h100                                20m 11s            CREATED
```

#### Step 0: Validate Model (PASS)

<details>
<summary>Model Artifacts</summary>

**Total:** 11 files,  58G

| File | Size |
|------|------|
| `model-00001-of-00002.safetensors` | 46G |
| `model-00002-of-00002.safetensors` | 12G |
| `tokenizer.json` | 31M |
| `model.safetensors.index.json` | 117K |
| `README.md` | 26K |
| `chat_template.jinja` | 16K |
| `config.json` | 4.5K |
| `tokenizer_config.json` | 2.0K |
| `.gitattributes` | 1.7K |
| `processor_config.json` | 1.6K |
| `generation_config.json` | 208B |

</details>

##### Model Architecture

| Property | Value |
|----------|-------|
| **Architecture** | `Gemma4ForConditionalGeneration` |
| **Model type** | `gemma4` |
| **Parameters** | 32.7B (32,682,372,656) |
| **Model size (weights)** | 58.25 GB (62,546,177,752 bytes, bfloat16) |
| **Density** | **Dense** (no MoE) |
| **Hidden size** | 5,376 |
| **Intermediate (FFN) size** | 21,504 |
| **Num layers** | 60 |
| **Num attention heads** | 32 |
| **Num KV heads** | 16 |
| **Attention type** | Grouped-Query Attention (GQA, 2:1) |
| **Head dim** | 256 |
| **Global head dim** | 512 |
| **Vocab size** | 262,144 |
| **Max position embeddings** | 262,144 (256K tokens) |
| **Activation** | `gelu_pytorch_tanh` |
| **Tie word embeddings** | True |
| **Sliding window** | 1,024 tokens |
| **Vision encoder** | 27 layers, hidden=1152, heads=16, patch=16 |

> **Weight size derivation:**
>   Parameters × 2 bytes = 65,364,745,312 bytes (60.88 GB), but `tie_word_embeddings=true` means the embedding matrix (vocab × hidden = 262,144 × 5,376 = 1,409,286,144 params, 2.62 GB) is stored once on disk instead of twice (input embed + LM head). Disk size = 65,364,745,312 − 2,818,572,288 = 62,546,173,024 bytes ≈ 62,546,177,752 bytes (58.25 GB).

##### Attention Mechanism

The model uses a **hybrid attention** pattern across 60 layers:

- **Full attention:** 10 layers — attend to all tokens in the sequence
- **Sliding window attention:** 50 layers — attend to local window of 1024 tokens

Layer pattern (S=sliding, F=full, L=linear):
```
   0:S  1:S  2:S  3:S  4:S  5:F  6:S  7:S  8:S  9:S
  10:S 11:F 12:S 13:S 14:S 15:S 16:S 17:F 18:S 19:S
  20:S 21:S 22:S 23:F 24:S 25:S 26:S 27:S 28:S 29:F
  30:S 31:S 32:S 33:S 34:S 35:F 36:S 37:S 38:S 39:S
  40:S 41:F 42:S 43:S 44:S 45:S 46:S 47:F 48:S 49:S
  50:S 51:S 52:S 53:F 54:S 55:S 56:S 57:S 58:S 59:F
```

**Pattern:** Every 6th layer is full attention (layers 5, 11, 17, 23, 29, 35, 41, 47, 53, 59)

##### vLLM Serving Configuration

All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.
Below is the exact derivation for each parameter, showing how model properties map to serving config.

**Deployed values** (from `deployment-template.yml`):

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |

###### H100 (H100 80GB x 1) — `Standard_NC40ads_H100_v5`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for H100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

###### A100 (A100 80GB x 1) — `Standard_NC24ads_A100_v4`

| Parameter | Value |
|-----------|-------|
| `VLLM_TENSOR_PARALLEL_SIZE` | **2** (user override (--tp 2)) |
| `VLLM_MAX_MODEL_LEN` | **65,536** (64K tokens) |
| `VLLM_GPU_MEMORY_UTILIZATION` | **0.85** |
| `VLLM_MAX_NUM_SEQS` | **20** |
| `BENCHMARK_CONCURRENCIES` | `[2, 4, 8, 16, 20, 30, 32]` |

<details>
<summary>Derivation math for A100</summary>

**1. Tensor Parallel Size (TP)**

Minimum GPUs needed so model weights fit with room for KV cache:
```
model_size          = 62,546,177,752 bytes = 58.25 GB
per_gpu_vram        = 80 GB
gpu_mem_util        = 0.9
overhead            = 0.5 GB (CUDA context, activations)
per_gpu_budget      = 80 * 0.9 - 0.5 = 71.50 GB
weight_threshold    = per_gpu_budget * 0.85 = 60.77 GB

  TP=1: model_per_gpu = 58.25/1 = 58.25 GB  <= 60.77 GB  -> YES <-- minimum TP
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB  <= 60.77 GB  -> YES

  Minimum TP = 1 (model fits on 1 GPU(s))
  User override: --tp 2 (spreads weights thinner, more KV cache room)
  TP=2: model_per_gpu = 58.25/2 = 29.13 GB

Result: VLLM_TENSOR_PARALLEL_SIZE = 2 (user override (--tp 2))
```

**2. GPU Memory Utilization**

```
TP > 1 -> NCCL communication buffers need headroom
Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)
```

**3. Max Model Length (context window)**

Per-GPU KV cache budget determines how many tokens can be stored:
```
per_gpu_model       = 58.25 GB / 2 TP = 29.13 GB
per_gpu_kv_budget   = (80 * 0.85) - 29.13 - 0.5
                    = 68.00 - 29.13 - 0.5
                    = 38.37 GB
                    = 41,204,484,244 bytes

KV cache per token per layer (after TP split):
  KV heads per GPU  = max(16 / 2, 1) = 8
  full_kv/tok/layer = 2 (K+V) * 8 heads * 256 dim * 2 bytes
                    = 8,192 bytes

Total KV per token (all 60 KV-bearing layers):
  = 60 layers * 8192 bytes/layer
  = 491,520 bytes/token

Max tokens from KV budget:
  max_kv_tokens     = 41,204,484,244 / 491,520 = 83,830
  max_position_emb  = 262,144 (from config.json)
  clamped           = min(83,830, 262,144) = 83,830
  rounded (pow2)    = 2^floor(log2(83,830)) = 2^16 = 65,536

Result: VLLM_MAX_MODEL_LEN = 65,536 (64K)
```

**4. Max Num Seqs (batch size / max concurrent requests)**

How many concurrent sequences fit in KV cache at average sequence length:
```
  max_kv_tokens     = 83,830
  avg_seq_len       = 4096 (default assumption)
  batch             = 83,830 / 4096 = 20
  clamped           = min(max(20, 1), 256) = 20

Result: VLLM_MAX_NUM_SEQS = 20
```

**5. Benchmark Concurrencies**

Testing range up to 2x max_num_seqs to find the saturation point:
```
  max_num_seqs      = 20
  Power-of-2 series up to 2x:
    c=2 (>= 2, included)
    c=4 (>= 2, included)
    c=8 (>= 2, included)
    c=16 (>= 2, included)
    c=32 (> max_num_seqs, stress test)
    c=20 (= max_num_seqs, boundary)
    c=30 (= 1.5x max_num_seqs, overload probe)

Result: BENCHMARK_CONCURRENCIES = [2, 4, 8, 16, 20, 30, 32]
```

</details>

##### Persisted Benchmark Config

From `yaml/benchmark-config.yml` (hydrated by step 2, used by step 7):

| Setting | Value |
|---------|-------|
| Concurrencies | `[2, 4, 8, 16, 20, 30, 32]` |
| Max num seqs | `20` |

#### Step 1: Create Environment (PASS)

Environment: `vllm-server` v`1` | Image: `vllm/vllm-openai:latest`

#### Step 2: Create Deployment Template (PASS)

Template: `vllm-google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 3: Register Model (PASS)

Model: `google--gemma-4-31b-it` v`1` in registry `mabables-reg-feb26`

#### Step 4: Create Online Endpoint (PASS)

| SKU | Endpoint |
|-----|----------|
| H100 | `google--gemma-4-31b-it-h100` |
| A100 | `google--gemma-4-31b-it-a100` |

#### Step 5: Create Online Deployment (FAIL)

Deployment: `google--gemma-4-31b-it-vllm`

#### Step 6: Test Inference (SKIP)

#### Step 7: Benchmark (SKIP)


</details>



## Changelog

| Run | Status | Versions | SKUs | Duration | Steps | Failed |
|-----|--------|----------|------|----------|-------|--------|
| 2026-04-20_07-23-16 | FAILED | model=6  env=6  dt=6 | h100 a100 | 93m 19s | 7/8 passed | 7-benchmark |
| 2026-04-20_00-47-42 | FAILED | model=6  env=6  dt=6 | h100 a100 | 155m 57s | 7/8 passed | 7-benchmark |
| 2026-04-20_00-06-56 | FAILED | model=6  env=6  dt=6 | h100 a100 | 37m 35s | 6/8 passed | 6-test-inference |
| 2026-04-19_22-23-23 | FAILED | model=6  env=6  dt=6 | h100 a100 | 101m 38s | 5/8 passed | 5-create-online-deployment |
| 2026-04-19_20-24-55 | INCOMPLETE | | | | | |
| 2026-04-19_13-02-18 | INCOMPLETE | | | | | |
| 2026-04-19_13-01-23 | FAILED | model=2  env=2  dt=3 | h100 a100 | 0m 14s | 2/8 passed | 2-create-deployment-template |
| 2026-04-19_12-33-14 | PASSED | model=2  env=2  dt=3 | h100 a100 | 13m 0s | 8/8 passed | -- |
| 2026-04-19_12-27-26 | FAILED | model=2  env=2  dt=3 | h100 a100 | 0m 34s | 3/8 passed | 3-register-model |
| 2026-04-19_00-42-32 | PASSED | model=2  env=2  dt=2 | h100 a100 | 631m 3s | 8/8 passed | -- |
| 2026-04-19_00-02-44 | FAILED | model=1  env=1  dt=1 | h100 a100 | 35m 12s | 5/8 passed | 5-create-online-deployment |
