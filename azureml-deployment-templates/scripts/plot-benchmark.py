#!/usr/bin/env python3
"""Generate benchmark charts comparing A100 vs H100 from AIPerf CSV results.

Directory structure expected:
  BENCH_DIR/
    a100/c2_in200_out800/profile_export_aiperf.csv
    a100/c4_in200_out800/profile_export_aiperf.csv
    ...
    h100/c2_in200_out800/profile_export_aiperf.csv
    ...

Produces:
  - benchmark_{stat}.png (2×3) per stat (avg, p50, p90): A100 vs H100 per request shape
  - percentiles_{shape}.png (2×2) per shape: avg/p50/p90 comparison
  - errors.png (2×2): error counts, error rates, error breakdown by type
"""
import csv
import json
import os
import sys
import matplotlib.pyplot as plt
import numpy as np

BENCH_DIR = sys.argv[1] if len(sys.argv) > 1 else "deployment-template/logs/cli/benchmark"
MODEL_LABEL = os.environ.get("HF_MODEL_ID", sys.argv[2] if len(sys.argv) > 2 else "Unknown Model").split("/")[-1]
OUT_DIR = os.path.join(BENCH_DIR, "plots")
os.makedirs(OUT_DIR, exist_ok=True)

STATS = ["avg", "p50", "p90"]

# ── Auto-detect combo directories (supports a100/h100 or tp1-a100/tp2-h100) ──
def _detect_combos(bench_dir):
    combos = []
    if not os.path.isdir(bench_dir):
        return combos
    for entry in sorted(os.listdir(bench_dir)):
        entry_path = os.path.join(bench_dir, entry)
        if not os.path.isdir(entry_path):
            continue
        has_runs = any(
            e.startswith("c") and "_in" in e
            for e in os.listdir(entry_path)
            if os.path.isdir(os.path.join(entry_path, e))
        )
        if has_runs:
            combos.append((entry, entry.upper()))
    return combos

COMBOS = _detect_combos(BENCH_DIR)
if not COMBOS:
    print(f"ERROR: No benchmark combo directories found in {BENCH_DIR}")
    sys.exit(1)
print(f"Detected combos: {[c[1] for c in COMBOS]}")
GPUS = [c[0] for c in COMBOS]
GPU_LABELS = {c[0]: c[1] for c in COMBOS}

# Auto-detect concurrencies from benchmark directories
_detected = set()
for _gpu in GPUS:
    _gpu_dir = os.path.join(BENCH_DIR, _gpu)
    if os.path.isdir(_gpu_dir):
        for _entry in os.listdir(_gpu_dir):
            if _entry.startswith("c") and "_in" in _entry:
                _c = _entry.split("_")[0][1:]
                if _c.isdigit():
                    _detected.add(int(_c))
CONCURRENCIES = sorted(_detected) if _detected else [2, 4, 8, 16, 24, 48, 96]
print(f"Concurrencies: {CONCURRENCIES}")

# 4 request shapes: key, dir_pattern, display_name
SHAPES = [
    ("short_gen",    "c{c}_in200_out800",    "Short-Gen (200→800)"),
    ("short_prompt", "c{c}_in800_out200",    "Short-Prompt (800→200)"),
    ("long_gen",     "c{c}_in2000_out8000",  "Long-Gen (2000→8000)"),
    ("long_prompt",  "c{c}_in8000_out2000",  "Long-Prompt (8000→2000)"),
]

# Colors/markers: dynamic for N combos
_base_colors = ["#4C72B0", "#C44E52", "#55A868", "#8172B2", "#CCB974", "#64B5CD", "#E5AE38", "#6D904F"]
_base_markers = ["o", "s", "^", "D", "v", "P", "X", "*"]
GPU_COLORS = {c[0]: _base_colors[i % len(_base_colors)] for i, c in enumerate(COMBOS)}
GPU_MARKERS = {c[0]: _base_markers[i % len(_base_markers)] for i, c in enumerate(COMBOS)}
SHAPE_LINESTYLES = {
    "short_gen": "-", "short_prompt": "--",
    "long_gen": "-.", "long_prompt": ":",
}

# ── Load data: data[gpu][stat][run_name][metric] = value ─────────────────────
all_data = {gpu: {s: {} for s in STATS} for gpu in GPUS}

for gpu in GPUS:
    gpu_dir = os.path.join(BENCH_DIR, gpu)
    if not os.path.isdir(gpu_dir):
        print(f"WARNING: {gpu_dir} not found, skipping {gpu}")
        continue
    for entry in sorted(os.listdir(gpu_dir)):
        csv_path = os.path.join(gpu_dir, entry, "profile_export_aiperf.csv")
        if not os.path.isfile(csv_path):
            continue
        with open(csv_path) as f:
            reader = csv.reader(f)
            header = None
            rows_per_request = []
            rows_aggregate = []
            section = None
            for row in reader:
                if not row:
                    continue
                if row[0].strip() == "Metric":
                    header = [c.strip() for c in row]
                    section = "aggregate" if "Value" in header else "per_request"
                    continue
                if header is None:
                    continue
                if section == "per_request":
                    rows_per_request.append((header, row))
                else:
                    rows_aggregate.append((header, row))

            for stat in STATS:
                metrics = {}
                for hdr, row in rows_per_request:
                    key = row[0].strip()
                    if stat in hdr:
                        col = hdr.index(stat)
                        if col < len(row):
                            metrics[key] = row[col].strip()
                for hdr, row in rows_aggregate:
                    key = row[0].strip()
                    if "Value" in hdr:
                        col = hdr.index("Value")
                        if col < len(row):
                            metrics[key] = row[col].strip()
                all_data[gpu][stat][entry] = metrics

def get_vals(data, runs, metric):
    return [float(data.get(r, {}).get(metric, 0)) for r in runs]

def annotate_ms(ax, xs, ys):
    for xi, yi in zip(xs, ys):
        label = f"{yi/1000:.1f}s" if yi >= 1000 else f"{yi:,.0f}"
        ax.annotate(label, (xi, yi), textcoords="offset points",
                    xytext=(0, 8), ha="center", fontsize=7)

def annotate_float(ax, xs, ys, fmt="{:.1f}"):
    for xi, yi in zip(xs, ys):
        ax.annotate(fmt.format(yi), (xi, yi), textcoords="offset points",
                    xytext=(0, 8), ha="center", fontsize=7)

# ── Generate one merged 2×3 chart per stat ───────────────────────────────────
METRICS_ROW1 = [
    ("Output Token Throughput (tokens/sec)", "Output Tokens / sec", "Total Token Throughput (aggregate)", "{:,.0f}"),
    ("Request Throughput (requests/sec)", "Requests / sec", "Request Throughput (aggregate)", "{:.1f}"),
    ("Output Token Throughput Per User (tokens/sec/user)", "Tokens / sec / user", "Per-User Token Throughput ({stat})", "{:,.0f}"),
]
METRICS_ROW2 = [
    ("Request Latency (ms)", "Request Latency (ms)", "End-to-End Request Latency ({stat})", "ms"),
    ("Time to First Token (ms)", "TTFT (ms)", "Time to First Token ({stat})", "ms"),
    ("Inter Token Latency (ms)", "ITL (ms)", "Inter Token Latency ({stat})", "{:.1f}"),
]

for stat in STATS:
    suptitle_info = f"{MODEL_LABEL} · vLLM · {' vs '.join(GPU_LABELS[g] for g in GPUS)}  (metric: {stat})"
    fig, axes = plt.subplots(2, 3, figsize=(20, 11))

    for col, (metric, ylabel, title_tpl, fmt) in enumerate(METRICS_ROW1):
        ax = axes[0, col]
        for key, pat, shape_label in SHAPES:
            runs = [pat.format(c=c) for c in CONCURRENCIES]
            for gpu in GPUS:
                vals = get_vals(all_data[gpu][stat], runs, metric)
                ax.plot(CONCURRENCIES, vals, marker=GPU_MARKERS[gpu],
                        linestyle=SHAPE_LINESTYLES[key], color=GPU_COLORS[gpu],
                        label=f"{GPU_LABELS[gpu]} {shape_label}", linewidth=1.5, markersize=5, alpha=0.85)
        ax.set_xlabel("Concurrent Clients", fontsize=11); ax.set_ylabel(ylabel, fontsize=11)
        ax.set_title(title_tpl.format(stat=stat), fontsize=12, fontweight="bold")
        ax.legend(fontsize=6, ncol=2); ax.grid(alpha=0.3); ax.set_xticks(CONCURRENCIES)

    for col, (metric, ylabel, title_tpl, fmt) in enumerate(METRICS_ROW2):
        ax = axes[1, col]
        for key, pat, shape_label in SHAPES:
            runs = [pat.format(c=c) for c in CONCURRENCIES]
            for gpu in GPUS:
                vals = get_vals(all_data[gpu][stat], runs, metric)
                ax.plot(CONCURRENCIES, vals, marker=GPU_MARKERS[gpu],
                        linestyle=SHAPE_LINESTYLES[key], color=GPU_COLORS[gpu],
                        label=f"{GPU_LABELS[gpu]} {shape_label}", linewidth=1.5, markersize=5, alpha=0.85)
        ax.set_xlabel("Concurrent Clients", fontsize=11); ax.set_ylabel(ylabel, fontsize=11)
        ax.set_title(title_tpl.format(stat=stat), fontsize=12, fontweight="bold")
        ax.legend(fontsize=6, ncol=2); ax.grid(alpha=0.3); ax.set_xticks(CONCURRENCIES)

    fig.suptitle(f"Benchmark Results vs Concurrency — {' vs '.join(GPU_LABELS[g] for g in GPUS)}\n{suptitle_info}", fontsize=14, fontweight="bold")
    fig.tight_layout()
    p = os.path.join(OUT_DIR, f"benchmark_{stat}.png")
    fig.savefig(p, dpi=150); plt.close(fig); print(f"Saved: {p}")

# ── Charts comparing avg/p50/p90 per request shape (A100 vs H100) ───────────
STAT_STYLES = {
    "avg": {"marker": "o", "ls": "-"},
    "p50": {"marker": "s", "ls": "--"},
    "p90": {"marker": "^", "ls": "-."},
}

PERCENTILE_METRICS = [
    ("Request Latency (ms)", "Request Latency (ms)", "End-to-End Request Latency", "ms"),
    ("Output Token Throughput Per User (tokens/sec/user)", "Tokens / sec / user", "Per-User Token Throughput", "{:,.0f}"),
    ("Time to First Token (ms)", "TTFT (ms)", "Time to First Token", "ms"),
    ("Inter Token Latency (ms)", "ITL (ms)", "Inter Token Latency", "{:.1f}"),
]

for key, pat, shape_label in SHAPES:
    runs = [pat.format(c=c) for c in CONCURRENCIES]
    fig, axes = plt.subplots(2, 2, figsize=(14, 11))

    for idx, (metric, ylabel, title, fmt) in enumerate(PERCENTILE_METRICS):
        ax = axes[idx // 2, idx % 2]
        for gpu in GPUS:
            for stat, sty in STAT_STYLES.items():
                data = all_data[gpu][stat]
                vals = get_vals(data, runs, metric)
                ax.plot(CONCURRENCIES, vals, marker=sty["marker"], linestyle=sty["ls"],
                        color=GPU_COLORS[gpu], label=f"{GPU_LABELS[gpu]} {stat}",
                        linewidth=1.8, markersize=6, alpha=0.85)
        ax.set_xlabel("Concurrent Clients", fontsize=12); ax.set_ylabel(ylabel, fontsize=12)
        ax.set_title(title, fontsize=13, fontweight="bold")
        ax.legend(fontsize=8, ncol=2); ax.grid(alpha=0.3); ax.set_xticks(CONCURRENCIES)

    fig.suptitle(f"Percentile Comparison — {shape_label}  ({' vs '.join(GPU_LABELS[g] for g in GPUS)})\n"
                 f"{MODEL_LABEL} · vLLM  (avg vs p50 vs p90)\n"
                 f"Note: Throughput totals are aggregate (no percentile distribution) — see benchmark_*.png",
                 fontsize=13, fontweight="bold")
    fig.tight_layout()
    p = os.path.join(OUT_DIR, f"percentiles_{key}.png")
    fig.savefig(p, dpi=150); plt.close(fig); print(f"Saved: {p}")

# ── Errors & Timeouts chart ─────────────────────────────────────────────────
# Load error data from JSON files (richer than CSV)
error_data = {gpu: {} for gpu in GPUS}  # gpu -> run_name -> {errors, total, error_types}

for gpu in GPUS:
    gpu_dir = os.path.join(BENCH_DIR, gpu)
    if not os.path.isdir(gpu_dir):
        continue
    for entry in sorted(os.listdir(gpu_dir)):
        json_path = os.path.join(gpu_dir, entry, "profile_export_aiperf.json")
        if not os.path.isfile(json_path):
            continue
        with open(json_path) as f:
            d = json.load(f)
        err_count = d.get("error_request_count", {}).get("avg", 0)
        req_count = d.get("request_count", {}).get("avg", 0)
        # Parse error_summary for type breakdown
        error_types = {}
        for es in d.get("error_summary", []):
            details = es.get("error_details", {})
            etype = details.get("type", "Unknown")
            msg = details.get("message", "")
            # Classify: if "timed out" or "TimeoutError" in message, it's a timeout
            if "timeout" in msg.lower() or "timed out" in msg.lower():
                label = f"{etype} (timeout)"
            else:
                label = etype
            error_types[label] = error_types.get(label, 0) + es.get("count", 0)
        error_data[gpu][entry] = {
            "errors": err_count,
            "total": req_count + err_count,  # request_count excludes errors
            "error_types": error_types,
        }

# Build per-shape error series
n_combos = len(GPUS)
n_cols_err = max(2, min(n_combos, 2))
n_rows_err = 1 + (n_combos + n_cols_err - 1) // n_cols_err
fig, axes = plt.subplots(n_rows_err, n_cols_err, figsize=(16, 6 * n_rows_err))
if n_rows_err == 1:
    axes = axes.reshape(1, -1)

# Plot 1: Error Count (absolute)
ax = axes[0, 0]
for key, pat, shape_label in SHAPES:
    runs = [pat.format(c=c) for c in CONCURRENCIES]
    for gpu in GPUS:
        vals = [error_data[gpu].get(r, {}).get("errors", 0) for r in runs]
        ax.plot(CONCURRENCIES, vals, marker=GPU_MARKERS[gpu],
                linestyle=SHAPE_LINESTYLES[key], color=GPU_COLORS[gpu],
                label=f"{GPU_LABELS[gpu]} {shape_label}", linewidth=1.5, markersize=5, alpha=0.85)
ax.set_xlabel("Concurrent Clients", fontsize=11); ax.set_ylabel("Error Count", fontsize=11)
ax.set_title("Error Request Count vs Concurrency", fontsize=12, fontweight="bold")
ax.legend(fontsize=6, ncol=2); ax.grid(alpha=0.3); ax.set_xticks(CONCURRENCIES)

# Plot 2: Error Rate (%)
ax = axes[0, 1]
for key, pat, shape_label in SHAPES:
    runs = [pat.format(c=c) for c in CONCURRENCIES]
    for gpu in GPUS:
        vals = []
        for r in runs:
            info = error_data[gpu].get(r, {})
            total = info.get("total", 100)
            errs = info.get("errors", 0)
            vals.append((errs / total * 100) if total > 0 else 0)
        ax.plot(CONCURRENCIES, vals, marker=GPU_MARKERS[gpu],
                linestyle=SHAPE_LINESTYLES[key], color=GPU_COLORS[gpu],
                label=f"{GPU_LABELS[gpu]} {shape_label}", linewidth=1.5, markersize=5, alpha=0.85)
ax.set_xlabel("Concurrent Clients", fontsize=11); ax.set_ylabel("Error Rate (%)", fontsize=11)
ax.set_title("Error Rate (%) vs Concurrency", fontsize=12, fontweight="bold")
ax.legend(fontsize=6, ncol=2); ax.grid(alpha=0.3); ax.set_xticks(CONCURRENCIES)

# Stacked bar charts of error types per concurrency (one per combo)
for gpu_idx, gpu in enumerate(GPUS):
    row = 1 + gpu_idx // n_cols_err
    col = gpu_idx % n_cols_err
    if row >= n_rows_err or col >= n_cols_err:
        break
    ax = axes[row, col]
    # Collect all error types across all runs for this GPU
    all_types = set()
    for run_info in error_data[gpu].values():
        all_types.update(run_info.get("error_types", {}).keys())
    all_types = sorted(all_types)

    if not all_types:
        ax.text(0.5, 0.5, "No errors recorded", transform=ax.transAxes,
                ha="center", va="center", fontsize=14, color="gray")
        ax.set_title(f"{GPU_LABELS[gpu]} — Error Breakdown by Type", fontsize=12, fontweight="bold")
        continue

    # For each shape, create grouped bars
    bar_width = 0.18
    shape_offsets = np.arange(len(SHAPES)) * bar_width - (len(SHAPES) - 1) * bar_width / 2
    type_colors = plt.cm.Set2(np.linspace(0, 1, max(len(all_types), 1)))

    x = np.arange(len(CONCURRENCIES))
    for s_idx, (key, pat, shape_label) in enumerate(SHAPES):
        runs = [pat.format(c=c) for c in CONCURRENCIES]
        bottoms = np.zeros(len(CONCURRENCIES))
        for t_idx, etype in enumerate(all_types):
            vals = np.array([error_data[gpu].get(r, {}).get("error_types", {}).get(etype, 0) for r in runs])
            ax.bar(x + shape_offsets[s_idx], vals, bar_width, bottom=bottoms,
                   color=type_colors[t_idx], edgecolor="white", linewidth=0.5,
                   label=f"{shape_label}: {etype}" if s_idx == 0 or True else "")
            bottoms += vals

    ax.set_xlabel("Concurrent Clients", fontsize=11); ax.set_ylabel("Error Count", fontsize=11)
    ax.set_title(f"{GPU_LABELS[gpu]} — Error Breakdown by Type", fontsize=12, fontweight="bold")
    ax.set_xticks(x); ax.set_xticklabels(CONCURRENCIES)
    ax.grid(alpha=0.3, axis="y")
    # Deduplicate legend
    handles, labels = ax.get_legend_handles_labels()
    seen = {}
    unique_h, unique_l = [], []
    for h, l in zip(handles, labels):
        if l not in seen:
            seen[l] = True
            unique_h.append(h); unique_l.append(l)
    ax.legend(unique_h, unique_l, fontsize=5, ncol=1, loc="upper left")

# Hide unused subplots
for ci in range(n_combos, (n_rows_err - 1) * n_cols_err):
    row = 1 + ci // n_cols_err
    col = ci % n_cols_err
    if row < n_rows_err and col < n_cols_err:
        axes[row, col].set_visible(False)

fig.suptitle(f"Errors & Timeouts — {' vs '.join(GPU_LABELS[g] for g in GPUS)}\n"
             f"{MODEL_LABEL} · vLLM",
             fontsize=14, fontweight="bold")
fig.tight_layout()
p = os.path.join(OUT_DIR, "errors.png")
fig.savefig(p, dpi=150); plt.close(fig); print(f"Saved: {p}")
