#!/usr/bin/env bash
# generate-model-readme.sh — Generate/update a model-specific README.md
#
# Parses E2E logs, summary, inference results, and benchmark data to produce
# a human-readable status page. Each run gets its own section (latest on top)
# with sub-sections per pipeline step.
#
# Usage:
#   source env.sh  (sets MODEL_ROOT, HF_MODEL_ID, etc.)
#   bash generate-model-readme.sh [LOG_DIR]
#
# If LOG_DIR is not provided, generates sections for ALL runs found.
# Output: $MODEL_ROOT/README.md
#
# SECURITY: All API keys, tokens, auth headers, and credentials are scrubbed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Always re-derive resource names from HF_MODEL_ID to avoid stale env vars
unset MODEL_ROOT MODEL_SLUG MODEL_DIR MODEL_CONFIG YAML_DIR LOG_BASE
unset MODEL_NAME MODEL_VERSION TEMPLATE_NAME TEMPLATE_VERSION DEPLOYMENT_NAME
unset ENVIRONMENT_NAME ENVIRONMENT_VERSION ENDPOINT_NAME_A100 ENDPOINT_NAME_H100
unset INSTANCE_TYPE_A100 INSTANCE_TYPE_H100 AZUREML_DT_ROOT
source "$SCRIPT_DIR/env.sh"

README="$MODEL_ROOT/README.md"
LOG_BASE_DIR="$MODEL_ROOT/logs/e2e"

# ── Scrubbing function ──────────────────────────────────────────────────────
scrub() {
  sed -E \
    -e 's/(Authorization: Bearer )[^ "]+/\1***REDACTED***/gi' \
    -e 's/(api-key: )[^ "]+/\1***REDACTED***/gi' \
    -e 's/(Bearer )[a-zA-Z0-9_.~+/=-]{20,}/\1***REDACTED***/g' \
    -e 's/(primaryKey|secondaryKey)["'"'"']*[=: ]+["'"'"']*[a-zA-Z0-9_.~+/=-]{10,}/\1=***REDACTED***/gi' \
    -e 's/(API_KEY=)[^ ]+/\1***REDACTED***/g' \
    -e 's/(HF_TOKEN=)[^ ]+/\1***REDACTED***/g' \
    -e 's/(hf_)[a-zA-Z0-9]{10,}/\1***REDACTED***/g' \
    -e 's/(\?|&)(sig|se|st|sv|sp|sr|sks|skt|ske|skoid|sktid|skv)=[^& "]+/\1\2=***REDACTED***/g' \
    -e 's|https://[a-z0-9]+\.blob\.core\.windows\.net/[^ ]*\?[^ ]*|https://***.blob.core.windows.net/***?***REDACTED***|g' \
    -e 's/(eyJ)[a-zA-Z0-9_.-]{50,}/***JWT_REDACTED***/g'
}

# =============================================================================
# Generate Step 0: Model Validation section
# =============================================================================
# This reads from model-artifacts/ (config.json, index.json, file listing)
# and the calc-vllm-config.sh logic to produce exhaustive architecture +
# vLLM derivation documentation.
# =============================================================================
generate_step0_section() {
  local _log_dir="$1"
  local _log_file="$_log_dir/0-validate-model.log"
  local _step_status="SKIP"

  # Determine step status from summary or log
  if [[ -f "$_log_dir/summary.txt" ]]; then
    _step_status=$(grep '0-validate-model' "$_log_dir/summary.txt" 2>/dev/null | grep -oE '\[PASS\]|\[FAIL\]' | tr -d '[]' || echo "SKIP")
  elif [[ -f "$_log_file" ]]; then
    _step_status="RAN"
  fi

  local _section=""
  _section+="#### Step 0: Validate Model ($_step_status)
"

  # ── 1. Model Artifacts Info ──────────────────────────────────────────────
  if [[ -d "$MODEL_DIR" ]]; then
    _section+="
<details>
<summary>Model Artifacts</summary>

"
    local _total_size
    _total_size=$(du -sh "$MODEL_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    local _file_count
    _file_count=$(find "$MODEL_DIR" -type f | wc -l | tr -d ' ')
    _section+="**Total:** ${_file_count} files, ${_total_size}

| File | Size |
|------|------|
"
    # List files sorted by size (largest first)
    while IFS= read -r line; do
      local _fsize _fname
      _fsize=$(echo "$line" | awk '{print $1}')
      _fname=$(echo "$line" | awk '{$1=""; print substr($0,2)}' | sed "s|$MODEL_DIR/||")
      _section+="| \`$_fname\` | $_fsize |
"
    done < <(find "$MODEL_DIR" -type f -exec ls -lh {} \; 2>/dev/null | awk '{print $5, $NF}' | sort -rh)
    _section+="
</details>
"
  fi

  # ── 2. Model Architecture from config.json ──────────────────────────────
  if [[ -f "$MODEL_CONFIG" ]]; then
    local _arch_info
    _arch_info=$(python3 << 'PYEOF'
import json, os, sys

cfg_path = os.environ.get("MODEL_CONFIG", "")
idx_path = os.path.join(os.path.dirname(cfg_path), "model.safetensors.index.json")

cfg = json.load(open(cfg_path))
tc = cfg.get("text_config", cfg)

# Basic info
archs = cfg.get("architectures", ["unknown"])
model_type = cfg.get("model_type", tc.get("model_type", "unknown"))
dtype = tc.get("dtype", cfg.get("torch_dtype", "unknown"))

# Dense vs MoE
is_moe = tc.get("enable_moe_block", False) or tc.get("num_experts") not in (None, 0)
num_experts = tc.get("num_experts")
top_k = tc.get("top_k_experts")
expert_intermediate = tc.get("expert_intermediate_size")

# Dimensions
hidden = tc.get("hidden_size", 0)
intermediate = tc.get("intermediate_size", 0)
num_layers = tc.get("num_hidden_layers", 0)
num_attn_heads = tc.get("num_attention_heads", 0)
num_kv_heads = tc.get("num_key_value_heads", num_attn_heads)
head_dim = tc.get("head_dim", hidden // num_attn_heads if num_attn_heads else 0)
global_head_dim = tc.get("global_head_dim", 0)
vocab = tc.get("vocab_size", 0)
max_pos = tc.get("max_position_embeddings", 0)
sliding_window = tc.get("sliding_window")
tie_embeddings = tc.get("tie_word_embeddings", cfg.get("tie_word_embeddings", False))

# Attention mechanism analysis
layer_types = tc.get("layer_types", ["full_attention"] * num_layers)
n_full = sum(1 for t in layer_types if "full" in t)
n_sliding = sum(1 for t in layer_types if "sliding" in t)
n_linear = sum(1 for t in layer_types if t == "linear_attention")

# GQA analysis
if num_kv_heads == num_attn_heads:
    attn_type = "Multi-Head Attention (MHA)"
    gqa_ratio = 1
elif num_kv_heads == 1:
    attn_type = "Multi-Query Attention (MQA)"
    gqa_ratio = num_attn_heads
else:
    attn_type = f"Grouped-Query Attention (GQA, {num_attn_heads // num_kv_heads}:1)"
    gqa_ratio = num_attn_heads // num_kv_heads

# RoPE info
rope_params = tc.get("rope_parameters", {})
activation = tc.get("hidden_activation", tc.get("hidden_act", "unknown"))

# Parameter count and model size
total_params = 0
model_bytes = 0
if os.path.exists(idx_path):
    idx = json.load(open(idx_path))
    meta = idx.get("metadata", {})
    total_params = int(meta.get("total_parameters", 0))
    model_bytes = int(meta.get("total_size", 0))
    params_estimated = False
    # If total_parameters not in index, estimate from total_size / dtype_bytes
    if total_params == 0 and model_bytes > 0:
        total_params = model_bytes // 2  # bf16 = 2 bytes per param
        params_estimated = True
else:
    # Estimate
    model_bytes = 2 * num_layers * (4 * hidden * hidden + 2 * hidden)
    total_params = model_bytes // 2
    params_estimated = True

model_gb = model_bytes / (1024**3)

# Vision config
vc = cfg.get("vision_config")
has_vision = isinstance(vc, dict) and vc.get("num_hidden_layers", 0) > 0

# Format parameter count
def fmt_params(p):
    if p >= 1e12: return f"{p/1e12:.1f}T"
    if p >= 1e9: return f"{p/1e9:.1f}B"
    if p >= 1e6: return f"{p/1e6:.0f}M"
    return str(p)

# Weight size derivation
dtype_size = 2  # bf16
naive_bytes = total_params * dtype_size
naive_gb = naive_bytes / (1024**3)
embed_params = vocab * hidden
embed_bytes = embed_params * dtype_size
embed_gb = embed_bytes / (1024**3)
size_note = ""
if tie_embeddings and total_params > 0 and abs(naive_bytes - model_bytes) > 1_000_000:
    size_note = (
        f"  Parameters × {dtype_size} bytes = {naive_bytes:,} bytes ({naive_gb:.2f} GB), "
        f"but `tie_word_embeddings=true` means the embedding matrix "
        f"(vocab × hidden = {vocab:,} × {hidden:,} = {embed_params:,} params, {embed_gb:.2f} GB) "
        f"is stored once on disk instead of twice (input embed + LM head). "
        f"Disk size = {naive_bytes:,} − {embed_bytes:,} = {naive_bytes - embed_bytes:,} bytes "
        f"≈ {model_bytes:,} bytes ({model_gb:.2f} GB)."
    )

# Output
print("ARCH_TABLE_START")
print(f"| **Architecture** | `{', '.join(archs)}` |")
print(f"| **Model type** | `{model_type}` |")
_est = " ≈ estimated from weight size" if params_estimated else ""
print(f"| **Parameters** | {fmt_params(total_params)} ({total_params:,}){_est} |")
print(f"| **Model size (weights)** | {model_gb:.2f} GB ({model_bytes:,} bytes, {dtype}) |")
if is_moe:
    print(f"| **Model type** | **Mixture of Experts (MoE)** |")
    if num_experts: print(f"| **Num experts** | {num_experts} (top-{top_k} routing) |")
    if expert_intermediate: print(f"| **Expert FFN size** | {expert_intermediate:,} |")
else:
    print(f"| **Density** | **Dense** (no MoE) |")
print(f"| **Hidden size** | {hidden:,} |")
print(f"| **Intermediate (FFN) size** | {intermediate:,} |")
print(f"| **Num layers** | {num_layers} |")
print(f"| **Num attention heads** | {num_attn_heads} |")
print(f"| **Num KV heads** | {num_kv_heads} |")
print(f"| **Attention type** | {attn_type} |")
print(f"| **Head dim** | {head_dim} |")
if global_head_dim: print(f"| **Global head dim** | {global_head_dim} |")
print(f"| **Vocab size** | {vocab:,} |")
print(f"| **Max position embeddings** | {max_pos:,} ({max_pos // 1024}K tokens) |")
print(f"| **Activation** | `{activation}` |")
print(f"| **Tie word embeddings** | {tie_embeddings} |")
if sliding_window: print(f"| **Sliding window** | {sliding_window:,} tokens |")
if has_vision:
    v_layers = vc.get("num_hidden_layers", 0)
    v_hidden = vc.get("hidden_size", 0)
    v_heads = vc.get("num_attention_heads", 0)
    v_patch = vc.get("patch_size", 0)
    print(f"| **Vision encoder** | {v_layers} layers, hidden={v_hidden}, heads={v_heads}, patch={v_patch} |")
print("ARCH_TABLE_END")

# Weight size derivation note
print("SIZE_NOTE_START")
if size_note:
    print("")
    print("> **Weight size derivation:**")
    print(f"> {size_note}")
    print("")
print("SIZE_NOTE_END")

# Attention breakdown
print("ATTN_BREAKDOWN_START")
if n_sliding > 0 or n_linear > 0:
    print(f"The model uses a **hybrid attention** pattern across {num_layers} layers:")
    print(f"")
    if n_full > 0: print(f"- **Full attention:** {n_full} layers — attend to all tokens in the sequence")
    if n_sliding > 0: print(f"- **Sliding window attention:** {n_sliding} layers — attend to local window of {sliding_window} tokens")
    if n_linear > 0: print(f"- **Linear attention:** {n_linear} layers — O(n) complexity attention")
    print(f"")
    # Show the pattern
    pattern = []
    for i, lt in enumerate(layer_types):
        short = "F" if "full" in lt else ("S" if "sliding" in lt else "L")
        pattern.append(short)
    # Show pattern in groups of 10
    print("Layer pattern (S=sliding, F=full, L=linear):")
    print("```")
    for start in range(0, len(pattern), 10):
        chunk = pattern[start:start+10]
        labels = " ".join(f"{start+j:2d}:{c}" for j, c in enumerate(chunk))
        print(f"  {labels}")
    print("```")
    print(f"")
    print(f"**Pattern:** Every {num_layers // n_full}th layer is full attention (layers {', '.join(str(i) for i,t in enumerate(layer_types) if 'full' in t)})")
else:
    print(f"All {num_layers} layers use **full attention** (standard transformer).")
print("ATTN_BREAKDOWN_END")

# KV cache geometry (needed for vLLM section)
print("KV_GEOMETRY_START")
print(f"kv_heads={num_kv_heads}")
print(f"head_dim={head_dim}")
print(f"num_layers={num_layers}")
print(f"n_full_attn={n_full + n_sliding}")
print(f"n_linear_attn={n_linear}")
print(f"model_bytes={model_bytes}")
print(f"model_gb={model_gb:.4f}")
print(f"max_pos={max_pos}")
print(f"total_params={total_params}")
lin_kv = tc.get("linear_num_key_heads", 0)
lin_hd = tc.get("linear_key_head_dim", 0)
print(f"linear_kv_heads={lin_kv}")
print(f"linear_head_dim={lin_hd}")
# RoPE details
if rope_params:
    for rtype, rvals in rope_params.items():
        if not isinstance(rvals, dict):
            continue
        theta = rvals.get("rope_theta", "")
        rt = rvals.get("rope_type", "")
        prf = rvals.get("partial_rotary_factor", "")
        extras = []
        if theta: extras.append(f"theta={theta}")
        if rt: extras.append(f"type={rt}")
        if prf: extras.append(f"partial_rotary={prf}")
        print(f"rope_{rtype}={','.join(extras)}")
print("KV_GEOMETRY_END")
PYEOF
) 2>/dev/null || true

    if [[ -n "$_arch_info" ]]; then
      # Extract arch table
      local _arch_table
      _arch_table=$(echo "$_arch_info" | sed -n '/^ARCH_TABLE_START$/,/^ARCH_TABLE_END$/p' | grep -v 'START\|END')

      local _size_note
      _size_note=$(echo "$_arch_info" | sed -n '/^SIZE_NOTE_START$/,/^SIZE_NOTE_END$/p' | grep -v 'START\|END')

      local _attn_breakdown
      _attn_breakdown=$(echo "$_arch_info" | sed -n '/^ATTN_BREAKDOWN_START$/,/^ATTN_BREAKDOWN_END$/p' | grep -v 'START\|END')

      _section+="
##### Model Architecture

| Property | Value |
|----------|-------|
$_arch_table
$_size_note

##### Attention Mechanism

$_attn_breakdown
"
    fi
  fi

  # ── 3. vLLM Configuration Derivation ────────────────────────────────────
  local _bench_cfg="$YAML_DIR/benchmark-config.yml"
  local _dt_yaml="$YAML_DIR/deployment-template.yml"
  if [[ -f "$MODEL_CONFIG" ]]; then
    local _vllm_section
    _vllm_section=$(_BENCH_CFG="$_bench_cfg" _DT_YAML="$_dt_yaml" \
      _INST_H100="${INSTANCE_TYPE_H100}" _INST_A100="${INSTANCE_TYPE_A100}" \
      python3 << 'PYEOF'
import json, os, sys, math

cfg_path = os.environ.get("MODEL_CONFIG", "")
bench_cfg_path = os.environ.get("_BENCH_CFG", "")
dt_yaml_path = os.environ.get("_DT_YAML", "")
inst_h100 = os.environ.get("_INST_H100", "")
inst_a100 = os.environ.get("_INST_A100", "")
idx_path = os.path.join(os.path.dirname(cfg_path), "model.safetensors.index.json")

cfg = json.load(open(cfg_path))
tc = cfg.get("text_config", cfg)

hidden = tc.get("hidden_size", 4096)
num_layers = tc.get("num_hidden_layers", 32)
num_attn_heads = tc.get("num_attention_heads", 32)
num_kv_heads = tc.get("num_key_value_heads", num_attn_heads)
head_dim = tc.get("head_dim", hidden // num_attn_heads)
vocab = tc.get("vocab_size", 32000)
max_pos = tc.get("max_position_embeddings", 131072)
linear_kv_heads = tc.get("linear_num_key_heads", 0)
linear_head_dim = tc.get("linear_key_head_dim", 0)

layer_types = tc.get("layer_types", ["full_attention"] * num_layers)
n_full = sum(1 for t in layer_types if "full" in t or "sliding" in t)
n_linear = sum(1 for t in layer_types if t == "linear_attention")

if os.path.exists(idx_path):
    idx = json.load(open(idx_path))
    model_bytes = int(idx.get("metadata", {}).get("total_size", 0))
else:
    model_bytes = 2 * num_layers * (4 * hidden * hidden + 2 * hidden)

model_gb = model_bytes / (1024**3)
dtype_bytes = 2  # bf16

# Read actual deployed values from deployment-template.yml
deployed_tp = None
deployed_max_len = None
deployed_mem_util = None
deployed_max_seqs = None
if dt_yaml_path and os.path.exists(dt_yaml_path):
    try:
        import yaml
        with open(dt_yaml_path) as f:
            dt = yaml.safe_load(f)
        env_vars = {}
        if isinstance(dt, dict):
            # Check environment_variables (standard AzureML DT schema)
            for key in ("environment_variables", "env_vars"):
                if key in dt and isinstance(dt[key], dict):
                    env_vars = dt[key]
                    break
        deployed_tp = int(env_vars.get("VLLM_TENSOR_PARALLEL_SIZE", 0)) or None
        deployed_max_len = int(env_vars.get("VLLM_MAX_MODEL_LEN", 0)) or None
        deployed_mem_util = float(env_vars.get("VLLM_GPU_MEMORY_UTILIZATION", 0)) or None
        deployed_max_seqs = int(env_vars.get("VLLM_MAX_NUM_SEQS", 0)) or None
    except Exception:
        pass

# Read benchmark config
bench_concurrencies = []
bench_max_num_seqs = None
if bench_cfg_path and os.path.exists(bench_cfg_path):
    try:
        import yaml
        with open(bench_cfg_path) as f:
            bc = yaml.safe_load(f)
        b = bc.get("benchmark", {})
        bench_concurrencies = b.get("concurrencies", [])
        bench_max_num_seqs = b.get("max_num_seqs")
    except Exception:
        pass

# SKU → GPU resolution (same as calc-vllm-config.sh)
sku_map = {
    "Standard_NC24ads_A100_v4": (1, 80, "A100 80GB"),
    "Standard_NC48ads_A100_v4": (2, 80, "A100 80GB"),
    "Standard_NC40ads_H100_v5": (1, 80, "H100 80GB"),
    "Standard_NC80adis_H100_v5": (2, 80, "H100 80GB"),
    "Standard_ND96isr_H100_v5": (8, 80, "H100 80GB"),
    "Standard_ND96amsr_A100_v4": (8, 80, "A100 80GB"),
}

gpus = {}
if inst_h100 and inst_h100 in sku_map:
    ng, vram, label = sku_map[inst_h100]
    gpus["H100"] = {"vram_gb": vram, "label": label, "num_gpus": ng, "sku": inst_h100}
if inst_a100 and inst_a100 in sku_map:
    ng, vram, label = sku_map[inst_a100]
    gpus["A100"] = {"vram_gb": vram, "label": label, "num_gpus": ng, "sku": inst_a100}
if not gpus:
    gpus = {
        "H100": {"vram_gb": 80, "label": "H100 80GB", "num_gpus": 2, "sku": "unknown"},
        "A100": {"vram_gb": 80, "label": "A100 80GB", "num_gpus": 2, "sku": "unknown"},
    }

overhead_gb = 0.5
seq_len = 4096

print("##### vLLM Serving Configuration")
print("")
print("All vLLM parameters are **automatically calculated** from model architecture by `calc-vllm-config.sh`.")
print("Below is the exact derivation for each parameter, showing how model properties map to serving config.")
print("")

# Show actual deployed values first
if deployed_tp is not None:
    print("**Deployed values** (from `deployment-template.yml`):")
    print("")
    print("| Parameter | Value |")
    print("|-----------|-------|")
    if deployed_tp: print(f"| `VLLM_TENSOR_PARALLEL_SIZE` | **{deployed_tp}** |")
    if deployed_max_len: print(f"| `VLLM_MAX_MODEL_LEN` | **{deployed_max_len:,}** ({deployed_max_len // 1024}K tokens) |")
    if deployed_mem_util: print(f"| `VLLM_GPU_MEMORY_UTILIZATION` | **{deployed_mem_util}** |")
    if deployed_max_seqs: print(f"| `VLLM_MAX_NUM_SEQS` | **{deployed_max_seqs}** |")
    print("")

for sku_name, gpu in gpus.items():
    gpu_vram_gb = gpu["vram_gb"]
    num_gpus = gpu["num_gpus"]
    sku_id = gpu.get("sku", "")
    gpu_mem_util_default = 0.9

    per_gpu_budget = gpu_vram_gb * gpu_mem_util_default - overhead_gb

    # TP calculation — use deployed TP if available
    tp = 1
    while model_gb / tp > per_gpu_budget * 0.85:
        tp *= 2
    min_tp = tp

    # Use deployed TP if set (user override like --tp 2)
    if deployed_tp is not None and deployed_tp >= min_tp:
        tensor_parallel_size = deployed_tp
        tp_source = f"user override (--tp {deployed_tp})"
    else:
        tensor_parallel_size = min_tp
        tp_source = "auto-calculated minimum"

    # mem_util
    mem_util = 0.85 if tensor_parallel_size > 1 else gpu_mem_util_default

    # max_model_len
    per_gpu_model_gb = model_gb / tensor_parallel_size
    per_gpu_kv_budget_gb = gpu_vram_gb * mem_util - per_gpu_model_gb - overhead_gb
    per_gpu_kv_budget_bytes = per_gpu_kv_budget_gb * (1024**3)

    full_kv_heads_per_gpu = max(num_kv_heads // tensor_parallel_size, 1)
    linear_kv_heads_per_gpu = max(linear_kv_heads // tensor_parallel_size, 1) if linear_kv_heads > 0 else 0

    full_kv_per_token_per_layer = 2 * full_kv_heads_per_gpu * head_dim * dtype_bytes
    linear_kv_per_token_per_layer = 2 * linear_kv_heads_per_gpu * linear_head_dim * dtype_bytes if linear_kv_heads_per_gpu > 0 else 0

    total_kv_per_token = (
        n_full * full_kv_per_token_per_layer +
        n_linear * linear_kv_per_token_per_layer
    )

    max_kv_tokens = int(per_gpu_kv_budget_bytes / total_kv_per_token) if total_kv_per_token > 0 else 0
    max_model_len = min(max_pos, max_kv_tokens)
    if max_model_len >= 1024:
        max_model_len = 2 ** int(math.log2(max_model_len))

    # max_num_seqs
    batch = max_kv_tokens // seq_len if seq_len > 0 else max_kv_tokens // 4096
    max_num_seqs = min(max(batch, 1), 256)

    # Benchmark concurrencies
    bc = []
    c = 1
    while c <= max_num_seqs * 2:
        if c >= 2: bc.append(c)
        c *= 2
    mns_r = max(2, max_num_seqs)
    if mns_r not in bc: bc.append(mns_r)
    boundary = int(max_num_seqs * 1.5)
    if boundary >= 2 and boundary not in bc: bc.append(boundary)
    bc = sorted(set(bc))

    print(f"###### {sku_name} ({gpu['label']} x {num_gpus}) — `{sku_id}`")
    print("")

    # Final values table
    print("| Parameter | Value |")
    print("|-----------|-------|")
    print(f"| `VLLM_TENSOR_PARALLEL_SIZE` | **{tensor_parallel_size}** ({tp_source}) |")
    print(f"| `VLLM_MAX_MODEL_LEN` | **{max_model_len:,}** ({max_model_len // 1024}K tokens) |")
    print(f"| `VLLM_GPU_MEMORY_UTILIZATION` | **{mem_util}** |")
    print(f"| `VLLM_MAX_NUM_SEQS` | **{max_num_seqs}** |")
    print(f"| `BENCHMARK_CONCURRENCIES` | `[{', '.join(str(x) for x in bc)}]` |")
    print("")

    print("<details>")
    print(f"<summary>Derivation math for {sku_name}</summary>")
    print("")

    # Step 1: TP
    print("**1. Tensor Parallel Size (TP)**")
    print("")
    print("Minimum GPUs needed so model weights fit with room for KV cache:")
    print("```")
    print(f"model_size          = {model_bytes:,} bytes = {model_gb:.2f} GB")
    print(f"per_gpu_vram        = {gpu_vram_gb} GB")
    print(f"gpu_mem_util        = {gpu_mem_util_default}")
    print(f"overhead            = {overhead_gb} GB (CUDA context, activations)")
    print(f"per_gpu_budget      = {gpu_vram_gb} * {gpu_mem_util_default} - {overhead_gb} = {per_gpu_budget:.2f} GB")
    print(f"weight_threshold    = per_gpu_budget * 0.85 = {per_gpu_budget * 0.85:.2f} GB")
    print(f"")
    t = 1
    while t <= max(min_tp, tensor_parallel_size):
        fits = "YES" if model_gb / t <= per_gpu_budget * 0.85 else "NO"
        marker = " <-- minimum TP" if t == min_tp and model_gb / t <= per_gpu_budget * 0.85 else ""
        print(f"  TP={t}: model_per_gpu = {model_gb:.2f}/{t} = {model_gb/t:.2f} GB  {'<=' if fits=='YES' else '>'} {per_gpu_budget*0.85:.2f} GB  -> {fits}{marker}")
        t *= 2
    if tensor_parallel_size > min_tp:
        print(f"")
        print(f"  Minimum TP = {min_tp} (model fits on {min_tp} GPU(s))")
        print(f"  User override: --tp {tensor_parallel_size} (spreads weights thinner, more KV cache room)")
        print(f"  TP={tensor_parallel_size}: model_per_gpu = {model_gb:.2f}/{tensor_parallel_size} = {model_gb/tensor_parallel_size:.2f} GB")
    print(f"")
    print(f"Result: VLLM_TENSOR_PARALLEL_SIZE = {tensor_parallel_size} ({tp_source})")
    print("```")
    print("")

    # Step 2: mem_util
    print("**2. GPU Memory Utilization**")
    print("")
    print("```")
    if tensor_parallel_size > 1:
        print(f"TP > 1 -> NCCL communication buffers need headroom")
        print(f"Result: VLLM_GPU_MEMORY_UTILIZATION = 0.85 (reduced from default 0.9)")
    else:
        print(f"TP = 1 -> no NCCL overhead")
        print(f"Result: VLLM_GPU_MEMORY_UTILIZATION = {gpu_mem_util_default}")
    print("```")
    print("")

    # Step 3: max_model_len
    print("**3. Max Model Length (context window)**")
    print("")
    print("Per-GPU KV cache budget determines how many tokens can be stored:")
    print("```")
    print(f"per_gpu_model       = {model_gb:.2f} GB / {tensor_parallel_size} TP = {per_gpu_model_gb:.2f} GB")
    print(f"per_gpu_kv_budget   = ({gpu_vram_gb} * {mem_util}) - {per_gpu_model_gb:.2f} - {overhead_gb}")
    print(f"                    = {gpu_vram_gb * mem_util:.2f} - {per_gpu_model_gb:.2f} - {overhead_gb}")
    print(f"                    = {per_gpu_kv_budget_gb:.2f} GB")
    print(f"                    = {per_gpu_kv_budget_bytes:,.0f} bytes")
    print(f"")
    print(f"KV cache per token per layer (after TP split):")
    print(f"  KV heads per GPU  = max({num_kv_heads} / {tensor_parallel_size}, 1) = {full_kv_heads_per_gpu}")
    print(f"  full_kv/tok/layer = 2 (K+V) * {full_kv_heads_per_gpu} heads * {head_dim} dim * {dtype_bytes} bytes")
    print(f"                    = {full_kv_per_token_per_layer:,} bytes")
    if n_linear > 0:
        print(f"  linear_kv/tok/lay = 2 * {linear_kv_heads_per_gpu} * {linear_head_dim} * {dtype_bytes}")
        print(f"                    = {linear_kv_per_token_per_layer:,} bytes")
    print(f"")
    print(f"Total KV per token (all {n_full + n_linear} KV-bearing layers):")
    if n_linear > 0:
        print(f"  = ({n_full} full/sliding * {full_kv_per_token_per_layer}) + ({n_linear} linear * {linear_kv_per_token_per_layer})")
    else:
        print(f"  = {n_full} layers * {full_kv_per_token_per_layer} bytes/layer")
    print(f"  = {total_kv_per_token:,} bytes/token")
    print(f"")
    print(f"Max tokens from KV budget:")
    print(f"  max_kv_tokens     = {per_gpu_kv_budget_bytes:,.0f} / {total_kv_per_token:,} = {max_kv_tokens:,}")
    print(f"  max_position_emb  = {max_pos:,} (from config.json)")
    print(f"  clamped           = min({max_kv_tokens:,}, {max_pos:,}) = {min(max_pos, max_kv_tokens):,}")
    raw_clamped = min(max_pos, max_kv_tokens)
    print(f"  rounded (pow2)    = 2^floor(log2({raw_clamped:,})) = 2^{int(math.log2(raw_clamped))} = {max_model_len:,}")
    print(f"")
    print(f"Result: VLLM_MAX_MODEL_LEN = {max_model_len:,} ({max_model_len // 1024}K)")
    print("```")
    print("")

    # Step 4: max_num_seqs
    print("**4. Max Num Seqs (batch size / max concurrent requests)**")
    print("")
    print("How many concurrent sequences fit in KV cache at average sequence length:")
    print("```")
    print(f"  max_kv_tokens     = {max_kv_tokens:,}")
    print(f"  avg_seq_len       = {seq_len} (default assumption)")
    print(f"  batch             = {max_kv_tokens:,} / {seq_len} = {max_kv_tokens // seq_len}")
    print(f"  clamped           = min(max({batch}, 1), 256) = {max_num_seqs}")
    print(f"")
    print(f"Result: VLLM_MAX_NUM_SEQS = {max_num_seqs}")
    print("```")
    print("")

    # Step 5: Benchmark concurrencies
    print("**5. Benchmark Concurrencies**")
    print("")
    print("Testing range up to 2x max_num_seqs to find the saturation point:")
    print("```")
    print(f"  max_num_seqs      = {max_num_seqs}")
    print(f"  Power-of-2 series up to 2x:")
    series = []
    c = 1
    while c <= max_num_seqs * 2:
        if c >= 2:
            series.append(c)
            print(f"    c={c}" + (" (>= 2, included)" if c <= max_num_seqs else " (> max_num_seqs, stress test)"))
        c *= 2
    mns_r2 = max(2, max_num_seqs)
    if mns_r2 not in series:
        print(f"    c={mns_r2} (= max_num_seqs, boundary)")
    bnd = int(max_num_seqs * 1.5)
    if bnd >= 2 and bnd not in series:
        print(f"    c={bnd} (= 1.5x max_num_seqs, overload probe)")
    print(f"")
    print(f"Result: BENCHMARK_CONCURRENCIES = [{', '.join(str(x) for x in bc)}]")
    print("```")
    print("")

    print("</details>")
    print("")

# If benchmark-config.yml has been hydrated, show the actual persisted values
if bench_concurrencies:
    print("##### Persisted Benchmark Config")
    print("")
    print(f"From `yaml/benchmark-config.yml` (hydrated by step 2, used by step 7):")
    print("")
    print("| Setting | Value |")
    print("|---------|-------|")
    print(f"| Concurrencies | `{bench_concurrencies}` |")
    if bench_max_num_seqs is not None:
        print(f"| Max num seqs | `{bench_max_num_seqs}` |")
    print("")
PYEOF
) 2>/dev/null || true

    if [[ -n "$_vllm_section" ]]; then
      _section+="
$_vllm_section
"
    fi
  fi

  echo "$_section"
}

# =============================================================================
# Generate a complete run section (all steps)
# =============================================================================
generate_run_section() {
  local _log_dir="$1"
  local _is_latest="$2"  # "true" or "false" — controls <details open>
  local _run_ts
  _run_ts=$(basename "$_log_dir")

  # ── Parse summary.txt ────────────────────────────────────────────────────
  local SUMMARY_FILE="$_log_dir/summary.txt"
  local RUN_STATUS="unknown" RUN_PASSED=0 RUN_FAILED=0 RUN_TOTAL=0
  local RUN_TIME="" RUN_SKUS="" RUN_VERSIONS="" RUN_COMMAND="" FAILED_STEPS=""
  local STEP_TABLE=""

  if [[ -f "$SUMMARY_FILE" ]]; then
    RUN_SKUS=$(grep 'SKUs:' "$SUMMARY_FILE" 2>/dev/null | head -1 | sed 's/.*SKUs:[[:space:]]*//' || true)
    RUN_VERSIONS=$(grep 'Versions:' "$SUMMARY_FILE" 2>/dev/null | head -1 | sed 's/.*Versions:[[:space:]]*//' || true)
    RUN_TIME=$(grep 'Total time:' "$SUMMARY_FILE" 2>/dev/null | head -1 | sed 's/.*Total time:[[:space:]]*//' || true)
    RUN_COMMAND=$(grep 'Command:' "$SUMMARY_FILE" 2>/dev/null | head -1 | sed 's/.*Command:[[:space:]]*//' | scrub || true)
    RUN_PASSED=$(grep 'Passed:' "$SUMMARY_FILE" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1 || true)
    RUN_FAILED=$(grep 'Failed:' "$SUMMARY_FILE" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1 || true)
    RUN_TOTAL=$(grep 'Passed:' "$SUMMARY_FILE" 2>/dev/null | head -1 | grep -oE '[0-9]+' | tail -1 || true)
    FAILED_STEPS=$(grep 'Failed steps:' "$SUMMARY_FILE" 2>/dev/null | head -1 | sed 's/.*Failed steps:[[:space:]]*//' || true)
    if [[ "$RUN_FAILED" == "0" ]]; then
      RUN_STATUS="PASSED"
    else
      RUN_STATUS="FAILED"
    fi
    STEP_TABLE=$(awk '/^  STEP /,/^====/' "$SUMMARY_FILE" | grep -vE '^====|^  ----|^$' | head -20 || true)
  else
    _total_logs=$(ls "$_log_dir"/[0-7]-*.log 2>/dev/null | grep -v 'endpoint-\|deploy-\|inference-\|bench-' | wc -l | tr -d ' ' || echo 0)
    if pgrep -f "run-e2e-cli.*${HF_MODEL_ID}" >/dev/null 2>&1; then
      RUN_STATUS="IN PROGRESS"
    else
      RUN_STATUS="INCOMPLETE (no summary)"
    fi
    RUN_PASSED="?"
    RUN_FAILED="?"
    RUN_TOTAL="$_total_logs"
    RUN_TIME="unknown"
  fi

  local _status_icon="✅"
  [[ "$RUN_STATUS" == "FAILED" ]] && _status_icon="❌"
  [[ "$RUN_STATUS" == "IN PROGRESS" ]] && _status_icon="🔄"
  [[ "$RUN_STATUS" == *"INCOMPLETE"* ]] && _status_icon="⚠️"

  local _open_attr=""
  [[ "$_is_latest" == "true" ]] && _open_attr=" open"

  local _section=""
  _section+="<details${_open_attr}>
<summary><strong>${_run_ts}</strong> — ${_status_icon} ${RUN_STATUS} — ${RUN_PASSED:-0}/${RUN_TOTAL:-?} steps — ${RUN_TIME:-unknown}</summary>

| Field | Value |
|-------|-------|
| **Timestamp** | \`$_run_ts\` |
| **Status** | **$RUN_STATUS** |
| **Versions** | $RUN_VERSIONS |
| **SKUs** | $RUN_SKUS |
| **Total time** | $RUN_TIME |
| **Steps** | ${RUN_PASSED:-0}/${RUN_TOTAL:-?} passed |
| **Failed** | ${FAILED_STEPS:---} |

\`\`\`bash
$RUN_COMMAND
\`\`\`

### Pipeline Steps

\`\`\`
$(echo "$STEP_TABLE" | scrub)
\`\`\`

"

  # ── Step 0: Validate Model ──────────────────────────────────────────────
  _section+="$(generate_step0_section "$_log_dir")
"

  # ── Step 1: Create Environment ──────────────────────────────────────────
  local _step1_status="SKIP"
  if [[ -f "$SUMMARY_FILE" ]]; then
    _step1_status=$(grep '1-create-environment' "$SUMMARY_FILE" 2>/dev/null | grep -oE '\[PASS\]|\[FAIL\]' | tr -d '[]' || echo "SKIP")
  fi
  _section+="
#### Step 1: Create Environment ($_step1_status)

Environment: \`$ENVIRONMENT_NAME\` v\`${ENVIRONMENT_VERSION}\` | Image: \`${VLLM_IMAGE:-vllm/vllm-openai:latest}\`

"

  # ── Step 2: Create Deployment Template ──────────────────────────────────
  local _step2_status="SKIP"
  if [[ -f "$SUMMARY_FILE" ]]; then
    _step2_status=$(grep '2-create-deployment-template' "$SUMMARY_FILE" 2>/dev/null | grep -oE '\[PASS\]|\[FAIL\]' | tr -d '[]' || echo "SKIP")
  fi
  _section+="#### Step 2: Create Deployment Template ($_step2_status)

Template: \`${TEMPLATE_NAME}\` v\`${TEMPLATE_VERSION}\` in registry \`${AZUREML_REGISTRY}\`

"

  # ── Step 3: Register Model ─────────────────────────────────────────────
  local _step3_status="SKIP"
  if [[ -f "$SUMMARY_FILE" ]]; then
    _step3_status=$(grep '3-register-model' "$SUMMARY_FILE" 2>/dev/null | grep -oE '\[PASS\]|\[FAIL\]' | tr -d '[]' || echo "SKIP")
  fi
  _section+="#### Step 3: Register Model ($_step3_status)

Model: \`${MODEL_NAME}\` v\`${MODEL_VERSION}\` in registry \`${AZUREML_REGISTRY}\`

"

  # ── Step 4: Create Online Endpoint ─────────────────────────────────────
  local _step4_status="SKIP"
  if [[ -f "$SUMMARY_FILE" ]]; then
    _step4_status=$(grep '4-create-online-endpoint' "$SUMMARY_FILE" 2>/dev/null | grep -oE '\[PASS\]|\[FAIL\]' | tr -d '[]' || echo "SKIP")
  fi
  _section+="#### Step 4: Create Online Endpoint ($_step4_status)

| SKU | Endpoint |
|-----|----------|
| H100 | \`${ENDPOINT_NAME_H100}\` |
| A100 | \`${ENDPOINT_NAME_A100}\` |

"

  # ── Step 5: Create Online Deployment ───────────────────────────────────
  local _step5_status="SKIP"
  if [[ -f "$SUMMARY_FILE" ]]; then
    _step5_status=$(grep '5-create-online-deployment' "$SUMMARY_FILE" 2>/dev/null | grep -oE '\[PASS\]|\[FAIL\]' | tr -d '[]' || echo "SKIP")
  fi
  _section+="#### Step 5: Create Online Deployment ($_step5_status)

Deployment: \`${DEPLOYMENT_NAME}\`

"

  # ── Step 6: Test Inference ─────────────────────────────────────────────
  local _step6_status="SKIP"
  if [[ -f "$SUMMARY_FILE" ]]; then
    _step6_status=$(grep '6-test-inference' "$SUMMARY_FILE" 2>/dev/null | grep -oE '\[PASS\]|\[FAIL\]' | tr -d '[]' || echo "SKIP")
  fi

  local _inference_section=""
  for sku in h100 a100; do
    local _SKU
    _SKU=$(echo "$sku" | tr '[:lower:]' '[:upper:]')
    local md_report="$_log_dir/6-inference-${sku}.md"
    local json_report="$_log_dir/6-inference-${sku}.json"
    local log_file="$_log_dir/6-inference-${sku}.log"

    if [[ -f "$json_report" ]]; then
      local _summary
      _summary=$(python3 -c "
import json
with open('$json_report') as f:
    data = json.load(f)
s = data.get('summary', {})
print(f\"Passed: {s.get('passed',0)} | Failed: {s.get('failed',0)} | Unsupported: {s.get('unsupported',0)} | N/A: {s.get('not_applicable',0)} | Total: {s.get('total',0)}\")
" 2>/dev/null || echo "Error reading JSON report")

      _inference_section+="
##### $_SKU — llm-api-spec results

$_summary
"
      if [[ -f "$md_report" ]]; then
        local _table
        _table=$(awk '/^\| #/,/^$/' "$md_report" | head -40)
        if [[ -n "$_table" ]]; then
          _inference_section+="
$_table
"
        fi
      fi
    elif [[ -f "$log_file" ]]; then
      local _response
      _response=$(grep -A50 '"choices"' "$log_file" 2>/dev/null | head -20 | scrub || true)
      if [[ -n "$_response" ]]; then
        local _status="Received response"
        grep -q '"error"' "$log_file" 2>/dev/null && _status="ERROR"
        _inference_section+="
##### $_SKU — $_status

<details>
<summary>Response snippet</summary>

\`\`\`json
$(echo "$_response" | head -15)
\`\`\`

</details>
"
      fi
    fi
  done

  _section+="#### Step 6: Test Inference ($_step6_status)
$_inference_section
"

  # ── Step 7: Benchmark ──────────────────────────────────────────────────
  local _step7_status="SKIP"
  if [[ -f "$SUMMARY_FILE" ]]; then
    _step7_status=$(grep '7-benchmark' "$SUMMARY_FILE" 2>/dev/null | grep -oE '\[PASS\]|\[FAIL\]' | tr -d '[]' || echo "SKIP")
  fi

  local BENCH_DIR="$_log_dir/benchmark"
  local _bench_section=""
  if [[ -d "$BENCH_DIR" ]]; then
    for sku_dir in "$BENCH_DIR"/h100 "$BENCH_DIR"/a100; do
      [[ -d "$sku_dir" ]] || continue
      local sku_label
      sku_label=$(basename "$sku_dir")
      local _SKU_LABEL
      _SKU_LABEL=$(echo "$sku_label" | tr '[:lower:]' '[:upper:]')
      local run_count
      run_count=$(find "$sku_dir" -name "profile_export_aiperf.json" 2>/dev/null | wc -l | tr -d ' ')
      local error_count=0
      if [[ $run_count -gt 0 ]]; then
        local _sample
        _sample=$(find "$sku_dir" -path "*/c2_in*_out*/profile_export_aiperf.json" 2>/dev/null | head -1)
        local _metrics=""
        if [[ -n "$_sample" && -f "$_sample" ]]; then
          _metrics=$(python3 -c "
import json
try:
    with open('$_sample') as f:
        d = json.load(f)
    ttft = d.get('time_to_first_token',{}).get('avg')
    itl = d.get('inter_token_latency',{}).get('avg')
    otps = d.get('output_token_throughput_per_request',{}).get('avg')
    parts = []
    if ttft is not None: parts.append(f'TTFT(avg): {float(ttft):.1f}ms')
    if itl is not None: parts.append(f'ITL(avg): {float(itl):.1f}ms')
    if otps is not None: parts.append(f'OT/s(avg): {float(otps):.1f} tok/s')
    print(' | '.join(parts) if parts else 'no metrics')
except Exception as e:
    print(f'error: {e}')
" 2>/dev/null || echo "metrics unavailable")
        fi
        error_count=$(python3 -c "
import json, glob
total = 0
for f in glob.glob('$sku_dir/*/profile_export_aiperf.json'):
    with open(f) as fh:
        d = json.load(fh)
        total += int(d.get('error_count',{}).get('avg',0))
print(total)
" 2>/dev/null || echo "0")

        _bench_section+="
##### $_SKU_LABEL

- **Benchmark runs:** $run_count
- **Total errors:** $error_count
- **Sample metrics (c=2):** $_metrics
"
      fi
    done
  fi

  _section+="#### Step 7: Benchmark ($_step7_status)
$_bench_section
"

  # ── Plots ────────────────────────────────────────────────────────────────
  local PLOTS_DIR="$BENCH_DIR/plots"
  if [[ -d "$PLOTS_DIR" ]]; then
    local _rel_plots="logs/e2e/$_run_ts/benchmark/plots"
    _section+="##### Benchmark Plots

"
    for plot in benchmark_avg.png benchmark_p50.png benchmark_p90.png errors.png; do
      if [[ -f "$PLOTS_DIR/$plot" ]]; then
        local _label
        _label=$(echo "$plot" | sed 's/.png//' | sed 's/_/ /g' | python3 -c "import sys; print(sys.stdin.read().strip().title())")
        _section+="###### $_label

![$_label]($_rel_plots/$plot)

"
      fi
    done

    local _perc_plots
    _perc_plots=$(ls "$PLOTS_DIR"/percentiles_*.png 2>/dev/null || true)
    if [[ -n "$_perc_plots" ]]; then
      _section+="<details>
<summary>Percentile breakdown by token shape</summary>

"
      for plot in "$PLOTS_DIR"/percentiles_*.png; do
        [[ -f "$plot" ]] || continue
        local _fname
        _fname=$(basename "$plot")
        local _label
        _label=$(echo "$_fname" | sed 's/.png//' | sed 's/_/ /g' | python3 -c "import sys; print(sys.stdin.read().strip().title())")
        _section+="###### $_label

![$_label]($_rel_plots/$_fname)

"
      done
      _section+="</details>
"
    fi
  fi

  _section+="
</details>

"
  echo "$_section"
}

# =============================================================================
# Main: collect all runs, generate README
# =============================================================================

# Collect all run directories (sorted newest first)
ALL_RUNS=()
if [[ -n "${1:-}" ]]; then
  ALL_RUNS=("$1")
fi

# Always discover all runs from the log base
for _run_dir in $(ls -1d "$LOG_BASE_DIR"/*/ 2>/dev/null | sort -r); do
  _run_dir="${_run_dir%/}"
  _already=false
  for _existing in "${ALL_RUNS[@]:-}"; do
    if [[ "$_existing" == "$_run_dir" ]]; then
      _already=true
      break
    fi
  done
  if [[ "$_already" != "true" ]]; then
    ALL_RUNS+=("$_run_dir")
  fi
done

if [[ ${#ALL_RUNS[@]} -eq 0 ]]; then
  echo "[WARN] No run directories found — skipping README generation."
  exit 0
fi

# ── Write README header ────────────────────────────────────────────────────
cat > "$README" << READMEEOF
# ${HF_MODEL_ID}

> Auto-generated status page — updated by E2E pipeline runs.
> Last updated: $(date '+%Y-%m-%d %H:%M:%S')

## Runs

READMEEOF

# ── Generate each run section (latest first, latest is open) ──────────────
_first=true
for _run_dir in "${ALL_RUNS[@]}"; do
  if $_first; then
    generate_run_section "$_run_dir" "true" >> "$README"
    _first=false
  else
    generate_run_section "$_run_dir" "false" >> "$README"
  fi
done

# ── Changelog table ──────────────────────────────────────────────────────────
cat >> "$README" << 'LOGHEADEREOF'

## Changelog

| Run | Status | Versions | SKUs | Duration | Steps | Failed |
|-----|--------|----------|------|----------|-------|--------|
LOGHEADEREOF

for _run_dir in "${ALL_RUNS[@]}"; do
  _run_ts=$(basename "$_run_dir")
  _sum_file="$_run_dir/summary.txt"
  if [[ -f "$_sum_file" ]]; then
    _skus=$(grep 'SKUs:' "$_sum_file" 2>/dev/null | head -1 | sed 's/.*SKUs:[[:space:]]*//' || true)
    _vers=$(grep 'Versions:' "$_sum_file" 2>/dev/null | head -1 | sed 's/.*Versions:[[:space:]]*//' || true)
    _time=$(grep 'Total time:' "$_sum_file" 2>/dev/null | head -1 | sed 's/.*Total time:[[:space:]]*//' || true)
    _passed=$(grep 'Passed:' "$_sum_file" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1 || true)
    _total=$(grep 'Passed:' "$_sum_file" 2>/dev/null | head -1 | grep -oE '[0-9]+' | tail -1 || true)
    _failed=$(grep 'Failed:' "$_sum_file" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1 || true)
    _fsteps=$(grep 'Failed steps:' "$_sum_file" 2>/dev/null | head -1 | sed 's/.*Failed steps:[[:space:]]*//' || true)
    _status="PASSED"
    [[ "$_failed" != "0" ]] && _status="FAILED"
    echo "| $_run_ts | $_status | $_vers | $_skus | $_time | ${_passed:-0}/${_total:-?} passed | ${_fsteps:---} |" >> "$README"
  else
    echo "| $_run_ts | INCOMPLETE | | | | | |" >> "$README"
  fi
done

echo "[INFO] README updated: $README"
