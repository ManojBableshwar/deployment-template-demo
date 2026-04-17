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
"""
import csv
import os
import sys
import matplotlib.pyplot as plt
import numpy as np

BENCH_DIR = sys.argv[1] if len(sys.argv) > 1 else "deployment-template/logs/cli/benchmark"
OUT_DIR = os.path.join(BENCH_DIR, "plots")
os.makedirs(OUT_DIR, exist_ok=True)

CONCURRENCIES = [2, 4, 8, 16, 24, 48, 96]
STATS = ["avg", "p50", "p90"]
GPUS = ["a100", "h100"]
GPU_LABELS = {"a100": "A100", "h100": "H100"}

# 4 request shapes: key, dir_pattern, display_name
SHAPES = [
    ("short_gen",    "c{c}_in200_out800",    "Short-Gen (200→800)"),
    ("short_prompt", "c{c}_in800_out200",    "Short-Prompt (800→200)"),
    ("long_gen",     "c{c}_in2000_out8000",  "Long-Gen (2000→8000)"),
    ("long_prompt",  "c{c}_in8000_out2000",  "Long-Prompt (8000→2000)"),
]

# Colors/markers: gpu × shape combos
GPU_COLORS = {"a100": "#4C72B0", "h100": "#C44E52"}
GPU_MARKERS = {"a100": "o", "h100": "s"}
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
    suptitle_info = f"Qwen3.5-0.8B · vLLM · A100 vs H100 · max_num_seqs=48  (metric: {stat})"
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

    fig.suptitle(f"Benchmark Results vs Concurrency — A100 vs H100\n{suptitle_info}", fontsize=14, fontweight="bold")
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

    fig.suptitle(f"Percentile Comparison — {shape_label}  (A100 vs H100)\n"
                 f"Qwen3.5-0.8B · vLLM · max_num_seqs=48  (avg vs p50 vs p90)\n"
                 f"Note: Throughput totals are aggregate (no percentile distribution) — see benchmark_*.png",
                 fontsize=13, fontweight="bold")
    fig.tight_layout()
    p = os.path.join(OUT_DIR, f"percentiles_{key}.png")
    fig.savefig(p, dpi=150); plt.close(fig); print(f"Saved: {p}")
