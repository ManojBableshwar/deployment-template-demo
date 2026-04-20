#!/usr/bin/env bash
# Calculate optimal vLLM max_num_seqs (batch size) for a given model + GPU.
#
# Usage:
#   ./calc-batch-size.sh                          # uses defaults from model config
#   ./calc-batch-size.sh --gpu h100               # specify GPU (a100-40, a100-80, h100)
#   ./calc-batch-size.sh --seq-len 4096           # average total sequence length
#   ./calc-batch-size.sh --gpu-mem-util 0.9       # vLLM gpu_memory_utilization
#
# The script reads model architecture from config.json and estimates how many
# concurrent sequences fit in the KV cache after model weights are loaded.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Defaults ─────────────────────────────────────────────────────────────────
GPU="h100"
GPU_MEM_UTIL="0.9"
SEQ_LEN=""           # average total sequence length (input+output); 0 = show table
OVERHEAD_GB="0.5"    # CUDA context, activations, etc.
MODEL_CONFIG="$ROOT_DIR/model-artifacts/config.json"

# ── Parse args ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gpu)           GPU="$2";           shift 2;;
    --gpu-mem-util)  GPU_MEM_UTIL="$2";  shift 2;;
    --seq-len)       SEQ_LEN="$2";       shift 2;;
    --overhead)      OVERHEAD_GB="$2";   shift 2;;
    --config)        MODEL_CONFIG="$2";  shift 2;;
    -h|--help)
      sed -n '2,11s/^# //p' "$0"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

# ── GPU VRAM lookup (GB) ─────────────────────────────────────────────────────
case "$GPU" in
  a100-40|a100_40) GPU_VRAM_GB=40;  GPU_LABEL="A100 40GB" ;;
  a100-80|a100_80|a100) GPU_VRAM_GB=80; GPU_LABEL="A100 80GB" ;;
  h100|h100-80|h100_80) GPU_VRAM_GB=80; GPU_LABEL="H100 80GB" ;;
  h200)            GPU_VRAM_GB=141; GPU_LABEL="H200 141GB" ;;
  *)
    # Allow raw number (e.g. --gpu 48)
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

# Extract text model params using python (handles JSON reliably)
read -r HIDDEN_SIZE NUM_LAYERS NUM_KV_HEADS HEAD_DIM VOCAB_SIZE MAX_POS MODEL_BYTES \
  LINEAR_KV_HEADS LINEAR_HEAD_DIM NUM_FULL_ATTN NUM_LINEAR_ATTN < <(
python3 -c "
import json, sys, os

cfg = json.load(open('$MODEL_CONFIG'))
tc = cfg.get('text_config', cfg)  # text_config or top-level

hidden = tc.get('hidden_size', 4096)
layers = tc.get('num_hidden_layers', 32)
kv_heads = tc.get('num_key_value_heads', tc.get('num_attention_heads', 32))
head_dim = tc.get('head_dim', hidden // tc.get('num_attention_heads', 32))
vocab = tc.get('vocab_size', 32000)
max_pos = tc.get('max_position_embeddings', 131072)

# Linear attention heads (Qwen3.5 hybrid)
lin_kv_heads = tc.get('linear_num_key_heads', 0)
lin_head_dim = tc.get('linear_key_head_dim', 0)

# Count full vs linear attention layers
layer_types = tc.get('layer_types', ['full_attention'] * layers)
n_full = sum(1 for t in layer_types if 'full' in t)
n_linear = sum(1 for t in layer_types if 'linear' in t)

# Model size from index or estimate
idx_path = os.path.join(os.path.dirname('$MODEL_CONFIG'), 'model.safetensors.index.json')
if os.path.exists(idx_path):
    model_bytes = json.load(open(idx_path))['metadata']['total_size']
else:
    # Rough estimate: 2 bytes per param for bf16
    model_bytes = 2 * layers * (4 * hidden * hidden + 2 * hidden)

print(hidden, layers, kv_heads, head_dim, vocab, max_pos, model_bytes,
      lin_kv_heads, lin_head_dim, n_full, n_linear)
" 2>/dev/null
)

# ── Compute KV cache budget ─────────────────────────────────────────────────
python3 -c "
import math

# GPU config
gpu_vram_gb     = $GPU_VRAM_GB
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

dtype_bytes = 2  # bf16

# Memory available for KV cache
usable_gb   = gpu_vram_gb * gpu_mem_util
model_gb    = model_bytes / (1024**3)
kv_budget_gb = usable_gb - model_gb - overhead_gb
kv_budget_bytes = kv_budget_gb * (1024**3)

# KV cache per token
# For full attention layers: 2 (K+V) × kv_heads × head_dim × dtype_bytes
full_kv_per_token_per_layer = 2 * num_kv_heads * head_dim * dtype_bytes
# For linear attention layers (hybrid models like Qwen3.5)
linear_kv_per_token_per_layer = 2 * linear_kv_heads * linear_head_dim * dtype_bytes if linear_kv_heads > 0 else 0

total_kv_per_token = (
    num_full_attn * full_kv_per_token_per_layer +
    num_linear_attn * linear_kv_per_token_per_layer
)

max_kv_tokens = int(kv_budget_bytes / total_kv_per_token) if total_kv_per_token > 0 else 0

# Print summary
print()
print('=' * 72)
print('  vLLM Batch Size Calculator')
print('=' * 72)
print()
print(f'  GPU:                {\"$GPU_LABEL\":<20}  VRAM: {gpu_vram_gb} GB')
print(f'  gpu_memory_util:    {gpu_mem_util}')
print(f'  Usable VRAM:        {usable_gb:.1f} GB')
print(f'  Model weights:      {model_gb:.2f} GB')
print(f'  Overhead:           {overhead_gb:.1f} GB')
print(f'  KV cache budget:    {kv_budget_gb:.2f} GB')
print()
print(f'  Model architecture:')
print(f'    hidden_size:      {hidden_size}')
print(f'    num_layers:       {num_layers} ({num_full_attn} full attn + {num_linear_attn} linear)')
print(f'    num_kv_heads:     {num_kv_heads} (full attn), {linear_kv_heads} (linear attn)')
print(f'    head_dim:         {head_dim} (full attn), {linear_head_dim} (linear attn)')
print(f'    max_position:     {max_pos:,}')
print(f'    dtype:            bf16 ({dtype_bytes} bytes)')
print()
print(f'  KV cache per token:')
print(f'    Full attn layer:  {full_kv_per_token_per_layer:,} bytes')
if linear_kv_per_token_per_layer:
    print(f'    Linear attn layer:{linear_kv_per_token_per_layer:,} bytes')
print(f'    Total (all layers): {total_kv_per_token:,} bytes ({total_kv_per_token/1024:.1f} KB)')
print()
print(f'  Max KV tokens:      {max_kv_tokens:,}')
print()

# Show table of batch sizes for common sequence lengths
seq_lens = [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072]

print('  ┌────────────┬────────────┬──────────────────────────────────┐')
print('  │  Avg Seq   │  Max Batch │  Recommendation                  │')
print('  │  Length    │  Size      │                                  │')
print('  ├────────────┼────────────┼──────────────────────────────────┤')

for sl in seq_lens:
    if sl > max_pos:
        continue
    batch = max_kv_tokens // sl if sl > 0 else 0
    if batch <= 0:
        note = '  ✗ Not enough memory'
    elif batch >= 256:
        note = f'  → use max_num_seqs=256 (vLLM cap)'
    elif batch >= 64:
        note = f'  → use max_num_seqs={min(batch, 256)}'
    elif batch >= 8:
        note = f'  → use max_num_seqs={batch}'
    else:
        note = f'  ⚠ Very constrained'
    print(f'  │ {sl:>8,}  │ {batch:>8,}  │{note:<34s}│')

print('  └────────────┴────────────┴──────────────────────────────────┘')
print()

# If specific seq_len requested, show recommendation
seq_len_arg = '$SEQ_LEN'
if seq_len_arg and seq_len_arg != '0':
    sl = int(seq_len_arg)
    batch = max_kv_tokens // sl
    recommended = min(batch, 256)
    print(f'  For avg sequence length {sl:,}:')
    print(f'    Theoretical max batch:  {batch}')
    print(f'    Recommended max_num_seqs: {recommended}')
    print()
    print(f'  vLLM flag:  --max-num-seqs {recommended}')
    print(f'  Or env var: VLLM_MAX_NUM_SEQS={recommended}')
    print()

# Important notes
print('  Notes:')
print('  • vLLM caps max_num_seqs at 256 by default')
print('  • Azure ML gateway cap (max_concurrent_requests_per_instance)')
print('    is often the real bottleneck (currently set to 10)')
print('  • Actual throughput depends on prefill/decode ratio')
print('  • Linear attention layers use less KV cache than full attention')
print('  • Add --extra-inputs ignore_eos:true to benchmark at full seq len')
print()
print('=' * 72)
"
