#!/usr/bin/env bash
# Calculate optimal vLLM configuration from model metadata + target GPU.
#
# Usage:
#   ./calc-vllm-config.sh                              # human-readable summary
#   ./calc-vllm-config.sh --gpu h100                   # specify GPU type
#   ./calc-vllm-config.sh --sku Standard_NC40ads_H100_v5  # resolve from Azure SKU
#   ./calc-vllm-config.sh --export                     # emit export VAR=val lines
#   ./calc-vllm-config.sh --yaml                       # emit YAML fragment
#   ./calc-vllm-config.sh --tp 2                        # override tensor parallelism
#   ./calc-vllm-config.sh --seq-len 4096               # tune max_num_seqs for avg len
#
# Computes:
#   VLLM_TENSOR_PARALLEL_SIZE  - GPUs needed to fit model weights
#   VLLM_MAX_MODEL_LEN         - max context length (clamped to KV budget)
#   VLLM_GPU_MEMORY_UTILIZATION - fraction of VRAM for vLLM
#   VLLM_MAX_NUM_SEQS          - max concurrent sequences (batch size)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Defaults ─────────────────────────────────────────────────────────────────
GPU=""
SKU=""
USER_TP=""          # user-specified TP override (empty = auto)
GPU_MEM_UTIL="0.9"
SEQ_LEN="4096"       # average total sequence length for max_num_seqs calc
OVERHEAD_GB="0.5"     # CUDA context, activations, etc.
# MODEL_CONFIG can be set externally (e.g. by env.sh); fall back to a sibling model-artifacts/
MODEL_CONFIG="${MODEL_CONFIG:-$(cd "$SCRIPT_DIR/.." && pwd)/model-artifacts/config.json}"
OUTPUT_MODE="summary" # summary | export | yaml

# ── Parse args ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gpu)           GPU="$2";           shift 2;;
    --sku)           SKU="$2";           shift 2;;
    --tp)            USER_TP="$2";       shift 2;;
    --gpu-mem-util)  GPU_MEM_UTIL="$2";  shift 2;;
    --seq-len)       SEQ_LEN="$2";       shift 2;;
    --overhead)      OVERHEAD_GB="$2";   shift 2;;
    --config)        MODEL_CONFIG="$2";  shift 2;;
    --export)        OUTPUT_MODE="export"; shift;;
    --yaml)          OUTPUT_MODE="yaml";   shift;;
    -h|--help)
      sed -n '2,16s/^# //p' "$0"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

# ── SKU → GPU resolution ─────────────────────────────────────────────────────
# Maps Azure VM SKU names to (num_gpus, gpu_type)
resolve_sku() {
  case "$1" in
    Standard_NC24ads_A100_v4)   echo "1 a100-80" ;;
    Standard_NC48ads_A100_v4)   echo "2 a100-80" ;;
    Standard_NC40ads_H100_v5)   echo "1 h100"    ;;
    Standard_NC80adis_H100_v5)  echo "2 h100"    ;;
    Standard_ND96isr_H100_v5)   echo "8 h100"    ;;
    Standard_ND96amsr_A100_v4)  echo "8 a100-80" ;;
    *) echo "" ;;
  esac
}

NUM_GPUS=1
if [[ -n "$SKU" ]]; then
  sku_info=$(resolve_sku "$SKU")
  if [[ -z "$sku_info" ]]; then
    echo "Unknown SKU: $SKU" >&2; exit 1
  fi
  NUM_GPUS=$(echo "$sku_info" | awk '{print $1}')
  GPU=$(echo "$sku_info" | awk '{print $2}')
elif [[ -z "$GPU" ]]; then
  GPU="h100"
fi

# ── GPU VRAM lookup (GB) ─────────────────────────────────────────────────────
case "$GPU" in
  a100-40|a100_40)             GPU_VRAM_GB=40;  GPU_LABEL="A100 40GB" ;;
  a100-80|a100_80|a100)        GPU_VRAM_GB=80;  GPU_LABEL="A100 80GB" ;;
  h100|h100-80|h100_80)        GPU_VRAM_GB=80;  GPU_LABEL="H100 80GB" ;;
  h200)                        GPU_VRAM_GB=141;  GPU_LABEL="H200 141GB" ;;
  *)
    if [[ "$GPU" =~ ^[0-9]+$ ]]; then
      GPU_VRAM_GB="$GPU"; GPU_LABEL="Custom ${GPU}GB"
    else
      echo "Unknown GPU: $GPU (use a100-40, a100-80, h100, h200, or a number)" >&2; exit 1
    fi ;;
esac

# ── Read model config ────────────────────────────────────────────────────────
if [[ ! -f "$MODEL_CONFIG" ]]; then
  echo "Model config not found: $MODEL_CONFIG" >&2; exit 1
fi

read -r HIDDEN_SIZE NUM_LAYERS NUM_KV_HEADS HEAD_DIM VOCAB_SIZE MAX_POS MODEL_BYTES \
  LINEAR_KV_HEADS LINEAR_HEAD_DIM NUM_FULL_ATTN NUM_LINEAR_ATTN < <(
python3 -c "
import json, os

cfg = json.load(open('$MODEL_CONFIG'))
tc = cfg.get('text_config', cfg)

hidden = tc.get('hidden_size', 4096)
layers = tc.get('num_hidden_layers', 32)
kv_heads = tc.get('num_key_value_heads', tc.get('num_attention_heads', 32))
head_dim = tc.get('head_dim', hidden // tc.get('num_attention_heads', 32))
vocab = tc.get('vocab_size', 32000)
max_pos = tc.get('max_position_embeddings', 131072)

lin_kv_heads = tc.get('linear_num_key_heads', 0)
lin_head_dim = tc.get('linear_key_head_dim', 0)

layer_types = tc.get('layer_types', ['full_attention'] * layers)
# Count all KV-bearing layer types: full_attention, sliding_attention, linear_attention
# Every layer that does attention needs KV cache
n_full = sum(1 for t in layer_types if 'full' in t or 'sliding' in t)
n_linear = sum(1 for t in layer_types if t == 'linear_attention')

idx_path = os.path.join(os.path.dirname('$MODEL_CONFIG'), 'model.safetensors.index.json')
if os.path.exists(idx_path):
    model_bytes = json.load(open(idx_path))['metadata']['total_size']
else:
    model_bytes = 2 * layers * (4 * hidden * hidden + 2 * hidden)

print(hidden, layers, kv_heads, head_dim, vocab, max_pos, model_bytes,
      lin_kv_heads, lin_head_dim, n_full, n_linear)
" 2>/dev/null
)

# ── Compute all vLLM parameters ─────────────────────────────────────────────
_CALC_OUTPUT=$(
python3 -c "
user_tp = ${USER_TP:-0}  # 0 means auto
import math

# GPU config
gpu_vram_gb     = $GPU_VRAM_GB
num_gpus        = $NUM_GPUS
gpu_mem_util    = $GPU_MEM_UTIL
overhead_gb     = $OVERHEAD_GB

# Model config
hidden_size     = $HIDDEN_SIZE
num_layers      = $NUM_LAYERS
num_kv_heads    = $NUM_KV_HEADS
head_dim        = $HEAD_DIM
vocab_size      = $VOCAB_SIZE
max_pos         = $MAX_POS
model_bytes     = $MODEL_BYTES
linear_kv_heads = $LINEAR_KV_HEADS
linear_head_dim = $LINEAR_HEAD_DIM
num_full_attn   = $NUM_FULL_ATTN
num_linear_attn = $NUM_LINEAR_ATTN

seq_len         = $SEQ_LEN
dtype_bytes     = 2  # bf16

model_gb = model_bytes / (1024**3)

# ── 1) TENSOR_PARALLEL_SIZE ──────────────────────────────────────────────
# Minimum GPUs to fit model weights with headroom for KV cache
# Each GPU gets (model_gb / TP) of weights; needs to fit in (vram * util - overhead)
per_gpu_budget = gpu_vram_gb * gpu_mem_util - overhead_gb
tp = 1
while model_gb / tp > per_gpu_budget * 0.85:  # 85% of budget for weights leaves room for KV
    tp *= 2
min_tp = tp  # minimum TP to fit model weights

import sys

# Apply user override if provided
if user_tp > 0:
    if user_tp < min_tp:
        print(f'FATAL: --tp {user_tp} is less than minimum TP={min_tp} required to fit model.', file=sys.stderr)
        print(f'  model_size={model_gb:.2f}GB  per_gpu_budget={per_gpu_budget:.2f}GB  threshold={per_gpu_budget*0.85:.2f}GB', file=sys.stderr)
        print(f'  Model weights ({model_gb:.2f}GB) cannot fit on {user_tp} GPU(s).', file=sys.stderr)
        sys.exit(1)
    if user_tp > min_tp:
        print(f'WARNING: --tp {user_tp} exceeds minimum TP={min_tp} needed to fit the model.', file=sys.stderr)
        print(f'  Model fits on {min_tp} GPU(s); using {user_tp} spreads weights thinner (more KV cache room).', file=sys.stderr)
    tensor_parallel_size = user_tp
else:
    tensor_parallel_size = min_tp

# Validate: TP must not exceed available GPUs on the SKU
if tensor_parallel_size > num_gpus:
    print(f'FATAL: TP={tensor_parallel_size} but SKU only has {num_gpus} GPU(s).', file=sys.stderr)
    print(f'  model_size={model_gb:.2f}GB  per_gpu_budget={per_gpu_budget:.2f}GB', file=sys.stderr)
    print(f'  Choose a SKU with at least {tensor_parallel_size} GPUs.', file=sys.stderr)
    sys.exit(1)
# Warn: TP < num_gpus means paying for idle GPUs
if tensor_parallel_size < num_gpus:
    print(f'WARNING: TP={tensor_parallel_size} uses only {tensor_parallel_size} of {num_gpus} GPUs on this SKU.', file=sys.stderr)
    print(f'  {num_gpus - tensor_parallel_size} GPU(s) will sit idle. Consider a smaller SKU or forcing TP={num_gpus}.', file=sys.stderr)

# ── 2) GPU_MEMORY_UTILIZATION ────────────────────────────────────────────
# Lower when TP > 1 (NCCL buffers need headroom), otherwise keep default
if tensor_parallel_size > 1:
    mem_util = 0.85
else:
    mem_util = float(gpu_mem_util)

# ── 3) MAX_MODEL_LEN ────────────────────────────────────────────────────
# Per-GPU memory after TP split
per_gpu_model_gb = model_gb / tensor_parallel_size
per_gpu_kv_budget_gb = gpu_vram_gb * mem_util - per_gpu_model_gb - overhead_gb
per_gpu_kv_budget_bytes = per_gpu_kv_budget_gb * (1024**3)

# KV cache per token (per GPU after TP: kv_heads are split across GPUs)
full_kv_heads_per_gpu = max(num_kv_heads // tensor_parallel_size, 1)
linear_kv_heads_per_gpu = max(linear_kv_heads // tensor_parallel_size, 1) if linear_kv_heads > 0 else 0

full_kv_per_token_per_layer = 2 * full_kv_heads_per_gpu * head_dim * dtype_bytes
linear_kv_per_token_per_layer = 2 * linear_kv_heads_per_gpu * linear_head_dim * dtype_bytes if linear_kv_heads_per_gpu > 0 else 0

total_kv_per_token = (
    num_full_attn * full_kv_per_token_per_layer +
    num_linear_attn * linear_kv_per_token_per_layer
)

max_kv_tokens = int(per_gpu_kv_budget_bytes / total_kv_per_token) if total_kv_per_token > 0 else 0

# Clamp to model's max_position_embeddings
max_model_len = min(max_pos, max_kv_tokens)
# Round down to nearest power of 2 for clean config (optional but conventional)
if max_model_len >= 1024:
    max_model_len = 2 ** int(math.log2(max_model_len))

# ── 4) MAX_NUM_SEQS ─────────────────────────────────────────────────────
if seq_len > 0:
    batch = max_kv_tokens // seq_len
else:
    batch = max_kv_tokens // 4096  # fallback
max_num_seqs = min(max(batch, 1), 256)  # vLLM caps at 256

# ── 5) BENCHMARK_CONCURRENCIES ──────────────────────────────────────────
# Estimate useful concurrency range based on max_num_seqs.
# Beyond ~2× max_num_seqs, requests just queue and cause timeouts.
# Generate a series: 1, 2, 4, ... up to 2× max_num_seqs (capped at reasonable values)
bench_concurrencies = []
c = 1
while c <= max_num_seqs * 2:
    if c >= 2:  # skip concurrency=1
        bench_concurrencies.append(c)
    c *= 2
# Always include max_num_seqs itself and 1.5× as boundary probe
mns_round = max(2, max_num_seqs)
if mns_round not in bench_concurrencies:
    bench_concurrencies.append(mns_round)
boundary = int(max_num_seqs * 1.5)
if boundary >= 2 and boundary not in bench_concurrencies:
    bench_concurrencies.append(boundary)
bench_concurrencies = sorted(set(bench_concurrencies))
bench_conc_str = ' '.join(str(c) for c in bench_concurrencies)

# ── Summary line for bash ────────────────────────────────────────────────
summary = (
    f'model={model_gb:.2f}GB '
    f'kv_budget={per_gpu_kv_budget_gb:.2f}GB/gpu '
    f'kv_per_tok={total_kv_per_token}B '
    f'max_kv_tok={max_kv_tokens} '
    f'seq_len={seq_len}'
)

print(tensor_parallel_size, max_model_len, mem_util, max_num_seqs, max_kv_tokens, bench_conc_str, '|', summary)
"
)

# Parse: "tp max_len mem_util max_seqs max_kv_tok conc1 conc2 ... | summary_text"
_PARAMS="${_CALC_OUTPUT%%|*}"
_SUMMARY="${_CALC_OUTPUT#*| }"
read -r VLLM_TENSOR_PARALLEL_SIZE VLLM_MAX_MODEL_LEN VLLM_GPU_MEMORY_UTILIZATION VLLM_MAX_NUM_SEQS \
  BENCHMARK_MAX_KV_TOKENS _BENCH_CONC_REST <<< "$_PARAMS"
BENCHMARK_CONCURRENCIES="$_BENCH_CONC_REST"

# ── Output ───────────────────────────────────────────────────────────────────
case "$OUTPUT_MODE" in
  export)
    echo "export VLLM_TENSOR_PARALLEL_SIZE=\"$VLLM_TENSOR_PARALLEL_SIZE\""
    echo "export VLLM_MAX_MODEL_LEN=\"$VLLM_MAX_MODEL_LEN\""
    echo "export VLLM_GPU_MEMORY_UTILIZATION=\"$VLLM_GPU_MEMORY_UTILIZATION\""
    echo "export VLLM_MAX_NUM_SEQS=\"$VLLM_MAX_NUM_SEQS\""
    echo "export BENCHMARK_MAX_KV_TOKENS=\"$BENCHMARK_MAX_KV_TOKENS\""
    echo "export BENCHMARK_CONCURRENCIES=\"$BENCHMARK_CONCURRENCIES\""
    ;;
  yaml)
    echo "  VLLM_TENSOR_PARALLEL_SIZE: \"$VLLM_TENSOR_PARALLEL_SIZE\""
    echo "  VLLM_MAX_MODEL_LEN: \"$VLLM_MAX_MODEL_LEN\""
    echo "  VLLM_GPU_MEMORY_UTILIZATION: \"$VLLM_GPU_MEMORY_UTILIZATION\""
    echo "  VLLM_MAX_NUM_SEQS: \"$VLLM_MAX_NUM_SEQS\""
    echo "  # BENCHMARK_MAX_KV_TOKENS: $BENCHMARK_MAX_KV_TOKENS"
    echo "  # BENCHMARK_CONCURRENCIES: $BENCHMARK_CONCURRENCIES"
    ;;
  summary)
    echo ""
    echo "========================================================================"
    echo "  vLLM Config Calculator"
    echo "========================================================================"
    echo ""
    echo "  GPU:    $GPU_LABEL × $NUM_GPUS    $([ -n "$SKU" ] && echo "(SKU: $SKU)")"
    echo "  Model:  $MODEL_CONFIG"
    echo "  Detail: $_SUMMARY"
    echo ""
    echo "  ┌──────────────────────────────────┬──────────┐"
    echo "  │  Parameter                       │  Value   │"
    echo "  ├──────────────────────────────────┼──────────┤"
    printf "  │  VLLM_TENSOR_PARALLEL_SIZE       │  %-7s │\n" "$VLLM_TENSOR_PARALLEL_SIZE"
    printf "  │  VLLM_MAX_MODEL_LEN              │  %-7s │\n" "$VLLM_MAX_MODEL_LEN"
    printf "  │  VLLM_GPU_MEMORY_UTILIZATION      │  %-7s │\n" "$VLLM_GPU_MEMORY_UTILIZATION"
    printf "  │  VLLM_MAX_NUM_SEQS               │  %-7s │\n" "$VLLM_MAX_NUM_SEQS"
    echo "  └──────────────────────────────────┴──────────┘"
    echo ""
    echo "  Benchmark concurrencies: $BENCHMARK_CONCURRENCIES"
    echo "    (based on max_num_seqs=$VLLM_MAX_NUM_SEQS; testing up to 2× to find saturation)"
    echo ""
    echo "  To use: eval \"\$($(basename "$0") --export)\""
    echo ""
    ;;
esac
