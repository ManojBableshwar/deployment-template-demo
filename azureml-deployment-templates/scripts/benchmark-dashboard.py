#!/usr/bin/env python3
"""Generate an interactive HTML dashboard from AIPerf benchmark results.

Usage:
  # All models
  python3 benchmark-dashboard.py azureml-deployment-templates/models --open

  # Single model's benchmark dir
  python3 benchmark-dashboard.py .../logs/e2e/2026-04-23_12-30-54/benchmark --open

  # Single e2e run
  python3 benchmark-dashboard.py .../logs/e2e/2026-04-23_12-30-54 --open

Accepts any directory — auto-detects whether it's:
  - models/ root (scans all models)
  - A benchmark/ directory (tp*-*/c*_in*_out*/)
  - An e2e timestamp directory (contains benchmark/)
  - Any directory containing profile_export_aiperf.json files

Produces a single self-contained HTML file with embedded Plotly.js charts.
"""

import argparse
import html
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path


def _scan_benchmark_dir(bench_dir: Path, model_name: str, e2e_run: str) -> list[dict]:
    """Scan a single benchmark/ directory for combo dirs and run dirs."""
    runs = []
    for combo_dir in sorted(bench_dir.iterdir()):
        if not combo_dir.is_dir():
            continue
        combo = combo_dir.name
        if combo in ("plots", "tokenizer"):
            continue
        m = re.match(r"(?:tp(\d+)-)?(.*)", combo)
        if not m:
            continue
        tp = int(m.group(1)) if m.group(1) else 1
        gpu = m.group(2).upper()

        for run_dir in sorted(combo_dir.iterdir()):
            if not run_dir.is_dir():
                continue
            rm = re.match(r"c(\d+)_in(\d+)_out(\d+)", run_dir.name)
            if not rm:
                continue
            c, il, ol = int(rm.group(1)), int(rm.group(2)), int(rm.group(3))
            json_path = run_dir / "profile_export_aiperf.json"
            jsonl_path = run_dir / "profile_export.jsonl"
            if not json_path.exists():
                continue
            runs.append({
                "model": model_name,
                "combo": combo,
                "tp": tp,
                "gpu": gpu,
                "run_name": run_dir.name,
                "concurrency": c,
                "input_len": il,
                "output_len": ol,
                "shape_label": f"{il}→{ol}",
                "json_path": str(json_path),
                "jsonl_path": str(jsonl_path) if jsonl_path.exists() else None,
                "e2e_run": e2e_run,
            })
    return runs


def _infer_model_name(path: Path) -> str:
    """Walk up directory tree to find the model name (models/<model_name>/logs/...)."""
    parts = path.resolve().parts
    for i, part in enumerate(parts):
        if part == "models" and i + 1 < len(parts):
            return parts[i + 1]
    return path.resolve().name


def find_benchmark_runs(target_dir: str) -> list[dict]:
    """Discover benchmark runs from any directory layout.

    Handles:
      - models/ root:  models/<model>/logs/e2e/*/benchmark/...
      - benchmark/ dir: <target>/tp*-*/c*_in*_out*/
      - e2e timestamp dir: <target>/benchmark/tp*-*/...
      - any dir: recursive search for profile_export_aiperf.json
    """
    target = Path(target_dir)

    # Case 1: benchmark/ directory itself (contains combo dirs like tp1-a100/)
    has_combos = False
    if target.is_dir():
        for d in target.iterdir():
            if not d.is_dir() or d.name in ("plots", "tokenizer"):
                continue
            try:
                if any(sd.is_dir() and re.match(r"c\d+_in\d+_out\d+", sd.name) for sd in d.iterdir()):
                    has_combos = True
                    break
            except (PermissionError, OSError):
                continue

    if has_combos:
        model_name = _infer_model_name(target)
        e2e_run = target.parent.name if target.name == "benchmark" else target.name
        runs = _scan_benchmark_dir(target, model_name, e2e_run)
        if runs:
            return runs

    # Case 2: e2e timestamp dir (contains benchmark/ subdir)
    bench_subdir = target / "benchmark"
    if bench_subdir.is_dir():
        model_name = _infer_model_name(target)
        runs = _scan_benchmark_dir(bench_subdir, model_name, target.name)
        if runs:
            return runs

    # Case 3: models/ root — scan all models
    runs = []
    for model_dir in sorted(target.iterdir()):
        if not model_dir.is_dir():
            continue
        model_name = model_dir.name
        logs_dir = model_dir / "logs"
        if not logs_dir.exists():
            continue
        for bench_dir in sorted(logs_dir.rglob("benchmark")):
            if not bench_dir.is_dir():
                continue
            e2e_run = bench_dir.parent.name
            runs.extend(_scan_benchmark_dir(bench_dir, model_name, e2e_run))
    if runs:
        return runs

    # Case 4: fallback — recursive search for aiperf JSON files anywhere
    for json_file in sorted(target.rglob("profile_export_aiperf.json")):
        run_dir = json_file.parent
        rm = re.match(r"c(\d+)_in(\d+)_out(\d+)", run_dir.name)
        if not rm:
            continue
        c, il, ol = int(rm.group(1)), int(rm.group(2)), int(rm.group(3))
        combo_dir = run_dir.parent
        combo = combo_dir.name
        cm = re.match(r"(?:tp(\d+)-)?(.*)", combo)
        tp = int(cm.group(1)) if cm and cm.group(1) else 1
        gpu = (cm.group(2) if cm else combo).upper()
        model_name = _infer_model_name(run_dir)
        jsonl_path = run_dir / "profile_export.jsonl"
        runs.append({
            "model": model_name,
            "combo": combo,
            "tp": tp,
            "gpu": gpu,
            "run_name": run_dir.name,
            "concurrency": c,
            "input_len": il,
            "output_len": ol,
            "shape_label": f"{il}→{ol}",
            "json_path": str(json_file),
            "jsonl_path": str(jsonl_path) if jsonl_path.exists() else None,
            "e2e_run": combo_dir.parent.name,
        })
    return runs


def load_aggregate(json_path: str) -> dict:
    """Load aggregate metrics from profile_export_aiperf.json."""
    with open(json_path) as f:
        return json.load(f)


def load_per_request(jsonl_path: str, max_rows: int = 500) -> list[dict]:
    """Load per-request data from profile_export.jsonl.

    Returns list of flat dicts with key metrics.
    """
    rows = []
    with open(jsonl_path) as f:
        for i, line in enumerate(f):
            if i >= max_rows:
                break
            d = json.loads(line)
            meta = d.get("metadata", {})
            metrics = d.get("metrics", {})
            row = {
                "request_id": i,
                "session_num": meta.get("session_num", 0),
                "worker_id": meta.get("worker_id", 0),
            }
            for mk in ("request_latency", "time_to_first_token", "inter_token_latency",
                        "output_sequence_length", "input_sequence_length",
                        "output_token_throughput_per_user", "prefill_throughput_per_user",
                        "time_to_second_token"):
                val = metrics.get(mk, {})
                if isinstance(val, dict):
                    row[mk] = val.get("value", 0)
                else:
                    row[mk] = val
            rows.append(row)
    return rows


def build_dashboard_data(runs: list[dict]) -> dict:
    """Build the data structure consumed by the HTML dashboard."""
    # Organize: model -> combo -> shape -> sorted by concurrency
    aggregate = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    per_request_data = {}  # key: "model|combo|run_name" -> rows

    models = set()
    combos = set()
    shapes = set()
    tps = set()
    gpus = set()

    for run in runs:
        key = (run["model"], run["combo"], run["shape_label"])
        agg = load_aggregate(run["json_path"])

        entry = {
            "concurrency": run["concurrency"],
            "tp": run["tp"],
            "gpu": run["gpu"],
            # Core LLM metrics
            "output_token_throughput": agg.get("output_token_throughput", {}).get("avg", 0),
            "request_throughput": agg.get("request_throughput", {}).get("avg", 0),
            "total_token_throughput": agg.get("total_token_throughput", {}).get("avg", 0),
            # Latency
            "request_latency_avg": agg.get("request_latency", {}).get("avg", 0),
            "request_latency_p50": agg.get("request_latency", {}).get("p50", 0),
            "request_latency_p90": agg.get("request_latency", {}).get("p90", 0),
            "request_latency_p99": agg.get("request_latency", {}).get("p99", 0),
            "ttft_avg": agg.get("time_to_first_token", {}).get("avg", 0),
            "ttft_p50": agg.get("time_to_first_token", {}).get("p50", 0),
            "ttft_p90": agg.get("time_to_first_token", {}).get("p90", 0),
            "ttft_p99": agg.get("time_to_first_token", {}).get("p99", 0),
            "itl_avg": agg.get("inter_token_latency", {}).get("avg", 0),
            "itl_p50": agg.get("inter_token_latency", {}).get("p50", 0),
            "itl_p90": agg.get("inter_token_latency", {}).get("p90", 0),
            "itl_p99": agg.get("inter_token_latency", {}).get("p99", 0),
            "tpot_avg": agg.get("output_token_throughput_per_user", {}).get("avg", 0),
            "tpot_p50": agg.get("output_token_throughput_per_user", {}).get("p50", 0),
            "tpot_p90": agg.get("output_token_throughput_per_user", {}).get("p90", 0),
            # Errors
            "request_count": agg.get("request_count", {}).get("avg", 0),
            "error_count": len(agg.get("error_summary", [])),
            "error_total": sum(e.get("count", 0) for e in agg.get("error_summary", [])),
            # Prefill
            "prefill_tput_avg": agg.get("prefill_throughput_per_user", {}).get("avg", 0),
            # Duration
            "duration": agg.get("benchmark_duration", {}).get("avg", 0),
        }
        aggregate[run["model"]][run["combo"]][run["shape_label"]].append(entry)

        models.add(run["model"])
        combos.add(run["combo"])
        shapes.add(run["shape_label"])
        tps.add(run["tp"])
        gpus.add(run["gpu"])

        # Load per-request data (sample)
        if run["jsonl_path"]:
            pr_key = f"{run['model']}|{run['combo']}|{run['run_name']}"
            per_request_data[pr_key] = load_per_request(run["jsonl_path"], max_rows=300)

    # Sort each series by concurrency
    for model in aggregate:
        for combo in aggregate[model]:
            for shape in aggregate[model][combo]:
                aggregate[model][combo][shape].sort(key=lambda x: x["concurrency"])

    return {
        "aggregate": {m: {c: dict(s) for c, s in cs.items()} for m, cs in aggregate.items()},
        "per_request": per_request_data,
        "models": sorted(models),
        "combos": sorted(combos),
        "shapes": sorted(shapes),
        "tps": sorted(tps),
        "gpus": sorted(gpus),
    }


HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AIPerf Benchmark Dashboard</title>
<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
<style>
:root {
  --bg: #0d1117; --bg2: #161b22; --bg3: #21262d; --fg: #c9d1d9;
  --accent: #58a6ff; --green: #3fb950; --orange: #d29922; --red: #f85149;
  --border: #30363d;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, sans-serif;
       background: var(--bg); color: var(--fg); padding: 16px; }
h1 { font-size: 1.5rem; margin-bottom: 4px; color: var(--accent); }
.subtitle { font-size: 0.85rem; color: #8b949e; margin-bottom: 16px; }
.controls { display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 16px;
            background: var(--bg2); padding: 12px; border-radius: 8px; border: 1px solid var(--border); }
.control-group { display: flex; flex-direction: column; gap: 4px; }
.control-group label { font-size: 0.75rem; color: #8b949e; text-transform: uppercase; letter-spacing: 0.5px; }
.control-group select, .control-group input { background: var(--bg3); color: var(--fg); border: 1px solid var(--border);
  border-radius: 4px; padding: 6px 8px; font-size: 0.85rem; }
.control-group select { min-width: 160px; }
.tabs { display: flex; gap: 2px; margin-bottom: 16px; }
.tab { padding: 8px 16px; background: var(--bg2); color: #8b949e; border: 1px solid var(--border);
       border-radius: 6px 6px 0 0; cursor: pointer; font-size: 0.85rem; }
.tab.active { background: var(--bg3); color: var(--accent); border-bottom-color: var(--bg3); }
.tab-content { display: none; }
.tab-content.active { display: block; }
.chart-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 24px; }
.chart-grid.cols-3 { grid-template-columns: 1fr 1fr 1fr; }
.chart-box { background: var(--bg2); border: 1px solid var(--border); border-radius: 8px; padding: 8px; min-height: 380px; }
.summary-cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; margin-bottom: 24px; }
.card { background: var(--bg2); border: 1px solid var(--border); border-radius: 8px; padding: 16px; }
.card .label { font-size: 0.75rem; color: #8b949e; text-transform: uppercase; }
.card .value { font-size: 1.5rem; font-weight: 600; color: var(--accent); margin-top: 4px; }
.card .detail { font-size: 0.8rem; color: #8b949e; margin-top: 4px; }
@media (max-width: 900px) { .chart-grid { grid-template-columns: 1fr; } }
</style>
</head>
<body>

<h1>AIPerf Benchmark Dashboard</h1>
<div class="subtitle" id="subtitle"></div>

<div class="controls" id="controls"></div>

<div class="tabs" id="tabs">
  <div class="tab active" data-tab="overview">Overview</div>
  <div class="tab" data-tab="throughput">Throughput</div>
  <div class="tab" data-tab="latency">Latency</div>
  <div class="tab" data-tab="tp-scaling">TP Scaling</div>
  <div class="tab" data-tab="percentiles">Percentiles</div>
  <div class="tab" data-tab="per-request">Per-Request</div>
  <div class="tab" data-tab="errors">Errors</div>
</div>

<div class="tab-content active" id="tab-overview">
  <div class="summary-cards" id="summary-cards"></div>
  <div class="chart-grid" id="overview-charts"></div>
</div>
<div class="tab-content" id="tab-throughput">
  <div class="chart-grid" id="throughput-charts"></div>
</div>
<div class="tab-content" id="tab-latency">
  <div class="chart-grid" id="latency-charts"></div>
</div>
<div class="tab-content" id="tab-tp-scaling">
  <div class="chart-grid" id="tp-charts"></div>
</div>
<div class="tab-content" id="tab-percentiles">
  <div class="chart-grid" id="percentile-charts"></div>
</div>
<div class="tab-content" id="tab-per-request">
  <div class="chart-grid" id="per-request-charts"></div>
</div>
<div class="tab-content" id="tab-errors">
  <div class="chart-grid" id="error-charts"></div>
</div>

<script>
// ── Embedded data ──
const DATA = __DATA_PLACEHOLDER__;

const COLORS = ['#58a6ff','#f85149','#3fb950','#d29922','#bc8cff','#79c0ff','#ffa657','#ff7b72',
                '#7ee787','#d2a8ff','#a5d6ff','#ffc58b'];
const PLOTLY_LAYOUT_BASE = {
  paper_bgcolor: '#161b22', plot_bgcolor: '#161b22',
  font: { color: '#c9d1d9', size: 12 },
  xaxis: { gridcolor: '#30363d', zerolinecolor: '#30363d' },
  yaxis: { gridcolor: '#30363d', zerolinecolor: '#30363d' },
  margin: { t: 40, r: 20, b: 50, l: 60 },
  legend: { bgcolor: 'rgba(0,0,0,0)', font: { size: 10 } },
  hovermode: 'x unified',
};

function mkLayout(title, xlab, ylab, extra) {
  return Object.assign({}, PLOTLY_LAYOUT_BASE, {
    title: { text: title, font: { size: 14, color: '#c9d1d9' } },
    xaxis: Object.assign({}, PLOTLY_LAYOUT_BASE.xaxis, { title: xlab }),
    yaxis: Object.assign({}, PLOTLY_LAYOUT_BASE.yaxis, { title: ylab }),
  }, extra || {});
}

// ── State ──
let state = {
  models: DATA.models,
  selectedModels: [...DATA.models],
  selectedCombos: [...DATA.combos],
  selectedShapes: [...DATA.shapes],
  selectedStat: 'avg',
};

// ── Controls ──
function buildControls() {
  const c = document.getElementById('controls');
  c.innerHTML = '';

  // Model filter
  const mg = mkControlGroup('Models');
  const ms = document.createElement('select');
  ms.multiple = true; ms.size = Math.min(DATA.models.length, 4);
  DATA.models.forEach(m => { const o = document.createElement('option'); o.value = m; o.text = m; o.selected = true; ms.add(o); });
  ms.onchange = () => { state.selectedModels = [...ms.selectedOptions].map(o => o.value); render(); };
  mg.appendChild(ms); c.appendChild(mg);

  // Combo filter
  const cg = mkControlGroup('GPU Config');
  const cs = document.createElement('select');
  cs.multiple = true; cs.size = Math.min(DATA.combos.length, 5);
  DATA.combos.forEach(m => { const o = document.createElement('option'); o.value = m; o.text = m; o.selected = true; cs.add(o); });
  cs.onchange = () => { state.selectedCombos = [...cs.selectedOptions].map(o => o.value); render(); };
  cg.appendChild(cs); c.appendChild(cg);

  // Shape filter
  const sg = mkControlGroup('Request Shape');
  const ss = document.createElement('select');
  ss.multiple = true; ss.size = Math.min(DATA.shapes.length, 5);
  DATA.shapes.forEach(m => { const o = document.createElement('option'); o.value = m; o.text = m; o.selected = true; ss.add(o); });
  ss.onchange = () => { state.selectedShapes = [...ss.selectedOptions].map(o => o.value); render(); };
  sg.appendChild(ss); c.appendChild(sg);

  // Stat selector
  const stg = mkControlGroup('Percentile');
  const sts = document.createElement('select');
  ['avg','p50','p90','p99'].forEach(s => { const o = document.createElement('option'); o.value = s; o.text = s; sts.add(o); });
  sts.onchange = () => { state.selectedStat = sts.value; render(); };
  stg.appendChild(sts); c.appendChild(stg);
}

function mkControlGroup(label) {
  const d = document.createElement('div');
  d.className = 'control-group';
  const l = document.createElement('label');
  l.textContent = label;
  d.appendChild(l);
  return d;
}

// ── Tabs ──
document.querySelectorAll('.tab').forEach(tab => {
  tab.onclick = () => {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
    tab.classList.add('active');
    document.getElementById('tab-' + tab.dataset.tab).classList.add('active');
    render();
  };
});

// ── Helpers ──
function getFilteredSeries() {
  // Returns array of { model, combo, shape, data: [{concurrency, ...metrics}] }
  const series = [];
  for (const model of state.selectedModels) {
    const mc = DATA.aggregate[model];
    if (!mc) continue;
    for (const combo of state.selectedCombos) {
      const sc = mc[combo];
      if (!sc) continue;
      for (const shape of state.selectedShapes) {
        const data = sc[shape];
        if (!data || data.length === 0) continue;
        series.push({ model, combo, shape, data });
      }
    }
  }
  return series;
}

function seriesLabel(s) {
  const parts = [];
  if (state.selectedModels.length > 1) parts.push(s.model.replace(/--/g, '/'));
  parts.push(s.combo.toUpperCase());
  if (state.selectedShapes.length > 1) parts.push(s.shape);
  return parts.join(' · ');
}

function mkDiv(parent) {
  const d = document.createElement('div');
  d.className = 'chart-box';
  parent.appendChild(d);
  return d;
}

function fmtNum(n) { return n >= 1000 ? n.toLocaleString('en', {maximumFractionDigits: 0}) : n.toFixed(1); }

// ── Render ──
function render() {
  const activeTab = document.querySelector('.tab.active').dataset.tab;
  document.getElementById('subtitle').textContent =
    `${DATA.models.length} model(s) · ${DATA.combos.length} config(s) · ${DATA.shapes.length} shapes`;

  if (activeTab === 'overview') renderOverview();
  else if (activeTab === 'throughput') renderThroughput();
  else if (activeTab === 'latency') renderLatency();
  else if (activeTab === 'tp-scaling') renderTPScaling();
  else if (activeTab === 'percentiles') renderPercentiles();
  else if (activeTab === 'per-request') renderPerRequest();
  else if (activeTab === 'errors') renderErrors();
}

// ── Overview ──
function renderOverview() {
  const series = getFilteredSeries();
  const cards = document.getElementById('summary-cards');
  cards.innerHTML = '';

  // Summary stats — find peak values across all filtered runs
  let peakOutputTput = 0, peakReqTput = 0, minTTFT = Infinity, totalRuns = 0;
  let peakOutputLabel = '', peakReqLabel = '', minTTFTLabel = '';
  for (const s of series) {
    for (const d of s.data) {
      totalRuns++;
      if (d.output_token_throughput > peakOutputTput) {
        peakOutputTput = d.output_token_throughput;
        peakOutputLabel = `${s.combo} c=${d.concurrency} ${s.shape}`;
      }
      if (d.request_throughput > peakReqTput) {
        peakReqTput = d.request_throughput;
        peakReqLabel = `${s.combo} c=${d.concurrency} ${s.shape}`;
      }
      if (d.ttft_avg < minTTFT && d.ttft_avg > 0) {
        minTTFT = d.ttft_avg;
        minTTFTLabel = `${s.combo} c=${d.concurrency} ${s.shape}`;
      }
    }
  }

  function addCard(label, value, detail) {
    const c = document.createElement('div'); c.className = 'card';
    c.innerHTML = `<div class="label">${label}</div><div class="value">${value}</div><div class="detail">${detail}</div>`;
    cards.appendChild(c);
  }
  addCard('Benchmark Runs', totalRuns, `${state.selectedModels.length} model(s)`);
  addCard('Peak Output Tokens/s', fmtNum(peakOutputTput), peakOutputLabel);
  addCard('Peak Requests/s', fmtNum(peakReqTput), peakReqLabel);
  addCard('Min TTFT (avg)', minTTFT < Infinity ? fmtNum(minTTFT) + ' ms' : 'N/A', minTTFTLabel);

  // Overview mini-charts: output tput and latency
  const container = document.getElementById('overview-charts');
  container.innerHTML = '';
  plotMetric(container, series, 'output_token_throughput', 'Output Token Throughput', 'Tokens/sec');
  plotMetric(container, series, 'request_latency_' + state.selectedStat, `Request Latency (${state.selectedStat})`, 'ms');
  plotMetric(container, series, 'ttft_' + state.selectedStat, `TTFT (${state.selectedStat})`, 'ms');
  plotMetric(container, series, 'itl_' + state.selectedStat, `ITL (${state.selectedStat})`, 'ms');
}

// ── Throughput tab ──
function renderThroughput() {
  const series = getFilteredSeries();
  const container = document.getElementById('throughput-charts');
  container.innerHTML = '';
  plotMetric(container, series, 'output_token_throughput', 'Output Token Throughput', 'Tokens/sec');
  plotMetric(container, series, 'request_throughput', 'Request Throughput', 'Requests/sec');
  plotMetric(container, series, 'total_token_throughput', 'Total Token Throughput', 'Tokens/sec');
  plotMetric(container, series, 'tpot_' + state.selectedStat, `Per-User Token Throughput (${state.selectedStat})`, 'Tokens/sec/user');
}

// ── Latency tab ──
function renderLatency() {
  const series = getFilteredSeries();
  const container = document.getElementById('latency-charts');
  container.innerHTML = '';
  plotMetric(container, series, 'request_latency_' + state.selectedStat, `E2E Latency (${state.selectedStat})`, 'ms');
  plotMetric(container, series, 'ttft_' + state.selectedStat, `Time to First Token (${state.selectedStat})`, 'ms');
  plotMetric(container, series, 'itl_' + state.selectedStat, `Inter-Token Latency (${state.selectedStat})`, 'ms');
  plotMetric(container, series, 'prefill_tput_avg', 'Prefill Throughput (avg)', 'Tokens/sec/user');
}

// ── Generic line chart ──
function plotMetric(container, series, metricKey, title, yLabel) {
  const div = mkDiv(container);
  const traces = series.map((s, i) => ({
    x: s.data.map(d => d.concurrency),
    y: s.data.map(d => d[metricKey] || 0),
    name: seriesLabel(s),
    mode: 'lines+markers',
    line: { color: COLORS[i % COLORS.length], width: 2 },
    marker: { size: 6 },
    hovertemplate: '%{y:.1f}<extra>' + seriesLabel(s) + '</extra>',
  }));
  Plotly.newPlot(div, traces, mkLayout(title, 'Concurrent Clients', yLabel), { responsive: true });
}

// ── TP Scaling ──
function renderTPScaling() {
  const container = document.getElementById('tp-charts');
  container.innerHTML = '';

  if (DATA.tps.length < 2) {
    container.innerHTML = '<div class="chart-box" style="display:flex;align-items:center;justify-content:center;color:#8b949e;">Only one TP value found — TP scaling view requires multiple TP configs.</div>';
    return;
  }

  // Group by (model, gpu, shape) -> tp -> data
  const groups = {};
  for (const model of state.selectedModels) {
    const mc = DATA.aggregate[model];
    if (!mc) continue;
    for (const combo of state.selectedCombos) {
      const sc = mc[combo];
      if (!sc) continue;
      // Extract gpu from combo
      const cm = combo.match(/(?:tp\d+-)?(.+)/);
      const gpu = cm ? cm[1] : combo;
      const tm = combo.match(/tp(\d+)/);
      const tp = tm ? parseInt(tm[1]) : 1;

      for (const shape of state.selectedShapes) {
        const data = sc[shape];
        if (!data) continue;
        const gk = `${model}|${gpu}|${shape}`;
        if (!groups[gk]) groups[gk] = {};
        groups[gk][tp] = data;
      }
    }
  }

  // For each metric, plot TP1 vs TP2 vs ... grouped by (model, gpu, shape)
  const metrics = [
    ['output_token_throughput', 'Output Tokens/sec'],
    ['request_throughput', 'Requests/sec'],
    ['request_latency_' + state.selectedStat, 'E2E Latency (ms)'],
    ['ttft_' + state.selectedStat, 'TTFT (ms)'],
  ];

  for (const [metricKey, yLabel] of metrics) {
    const div = mkDiv(container);
    const traces = [];
    let ci = 0;
    for (const [gk, tpMap] of Object.entries(groups)) {
      const [model, gpu, shape] = gk.split('|');
      for (const [tp, data] of Object.entries(tpMap).sort((a,b) => a[0]-b[0])) {
        const label = `TP${tp} ${gpu.toUpperCase()}` + (state.selectedModels.length > 1 ? ` · ${model}` : '') +
                      (state.selectedShapes.length > 1 ? ` · ${shape}` : '');
        traces.push({
          x: data.map(d => d.concurrency),
          y: data.map(d => d[metricKey] || 0),
          name: label,
          mode: 'lines+markers',
          line: { color: COLORS[ci % COLORS.length], width: 2 },
          marker: { size: 6 },
        });
        ci++;
      }
    }
    Plotly.newPlot(div, traces, mkLayout(`TP Scaling — ${yLabel}`, 'Concurrent Clients', yLabel), { responsive: true });
  }
}

// ── Percentiles ──
function renderPercentiles() {
  const container = document.getElementById('percentile-charts');
  container.innerHTML = '';
  const series = getFilteredSeries();

  const pMetrics = [
    { base: 'request_latency', label: 'E2E Latency', unit: 'ms' },
    { base: 'ttft', label: 'TTFT', unit: 'ms' },
    { base: 'itl', label: 'ITL', unit: 'ms' },
    { base: 'tpot', label: 'Per-User Throughput', unit: 'tokens/sec/user' },
  ];

  for (const pm of pMetrics) {
    const div = mkDiv(container);
    const traces = [];
    let ci = 0;
    for (const s of series) {
      for (const pct of ['avg', 'p50', 'p90', 'p99']) {
        const key = pm.base + '_' + pct;
        const hasData = s.data.some(d => d[key] !== undefined && d[key] !== 0);
        if (!hasData) continue;
        traces.push({
          x: s.data.map(d => d.concurrency),
          y: s.data.map(d => d[key] || 0),
          name: `${seriesLabel(s)} ${pct}`,
          mode: 'lines+markers',
          line: { color: COLORS[ci % COLORS.length], width: pct === 'avg' ? 2.5 : 1.5,
                  dash: pct === 'p90' ? 'dash' : pct === 'p99' ? 'dot' : 'solid' },
          marker: { size: 5 },
        });
        ci++;
      }
    }
    Plotly.newPlot(div, traces, mkLayout(`${pm.label} — Percentile Distribution`, 'Concurrent Clients', pm.unit), { responsive: true });
  }
}

// ── Per-Request Scatter ──
function renderPerRequest() {
  const container = document.getElementById('per-request-charts');
  container.innerHTML = '';

  // Find matching per-request keys
  const matchingKeys = Object.keys(DATA.per_request).filter(k => {
    const [model, combo] = k.split('|');
    return state.selectedModels.includes(model) && state.selectedCombos.includes(combo);
  });

  if (matchingKeys.length === 0) {
    container.innerHTML = '<div class="chart-box" style="display:flex;align-items:center;justify-content:center;color:#8b949e;">No per-request data available for current selection.</div>';
    return;
  }

  // Limit to first 8 matching combos to avoid huge charts
  const keys = matchingKeys.slice(0, 8);

  // Scatter: latency vs output tokens
  const div1 = mkDiv(container);
  const traces1 = keys.map((k, i) => {
    const rows = DATA.per_request[k];
    const label = k.replace(/\|/g, ' · ');
    return {
      x: rows.map(r => r.output_sequence_length),
      y: rows.map(r => r.request_latency),
      name: label,
      mode: 'markers',
      marker: { color: COLORS[i % COLORS.length], size: 4, opacity: 0.6 },
      hovertemplate: 'OSL: %{x}<br>Latency: %{y:.0f}ms<extra>' + label + '</extra>',
    };
  });
  Plotly.newPlot(div1, traces1, mkLayout('Request Latency vs Output Length', 'Output Tokens', 'Latency (ms)'), { responsive: true });

  // Scatter: TTFT per request
  const div2 = mkDiv(container);
  const traces2 = keys.map((k, i) => {
    const rows = DATA.per_request[k];
    const label = k.replace(/\|/g, ' · ');
    return {
      x: rows.map((r, j) => j),
      y: rows.map(r => r.time_to_first_token),
      name: label,
      mode: 'markers',
      marker: { color: COLORS[i % COLORS.length], size: 4, opacity: 0.6 },
    };
  });
  Plotly.newPlot(div2, traces2, mkLayout('TTFT per Request', 'Request #', 'TTFT (ms)'), { responsive: true });

  // Histogram: latency distribution
  const div3 = mkDiv(container);
  const traces3 = keys.map((k, i) => {
    const rows = DATA.per_request[k];
    return {
      x: rows.map(r => r.request_latency),
      name: k.replace(/\|/g, ' · '),
      type: 'histogram',
      opacity: 0.6,
      marker: { color: COLORS[i % COLORS.length] },
      nbinsx: 40,
    };
  });
  Plotly.newPlot(div3, traces3, mkLayout('Latency Distribution', 'Latency (ms)', 'Count',
    { barmode: 'overlay' }), { responsive: true });

  // Scatter: per-user throughput vs request#
  const div4 = mkDiv(container);
  const traces4 = keys.map((k, i) => {
    const rows = DATA.per_request[k];
    return {
      x: rows.map((r, j) => j),
      y: rows.map(r => r.output_token_throughput_per_user),
      name: k.replace(/\|/g, ' · '),
      mode: 'markers',
      marker: { color: COLORS[i % COLORS.length], size: 4, opacity: 0.6 },
    };
  });
  Plotly.newPlot(div4, traces4, mkLayout('Per-User Throughput per Request', 'Request #', 'Tokens/sec/user'), { responsive: true });
}

// ── Errors ──
function renderErrors() {
  const container = document.getElementById('error-charts');
  container.innerHTML = '';
  const series = getFilteredSeries();

  // Error count vs concurrency
  const div1 = mkDiv(container);
  const traces1 = series.map((s, i) => ({
    x: s.data.map(d => d.concurrency),
    y: s.data.map(d => d.error_total),
    name: seriesLabel(s),
    mode: 'lines+markers',
    line: { color: COLORS[i % COLORS.length], width: 2 },
    marker: { size: 6 },
  }));
  Plotly.newPlot(div1, traces1, mkLayout('Error Count vs Concurrency', 'Concurrent Clients', 'Error Count'), { responsive: true });

  // Error rate %
  const div2 = mkDiv(container);
  const traces2 = series.map((s, i) => ({
    x: s.data.map(d => d.concurrency),
    y: s.data.map(d => {
      const total = d.request_count + d.error_total;
      return total > 0 ? (d.error_total / total * 100) : 0;
    }),
    name: seriesLabel(s),
    mode: 'lines+markers',
    line: { color: COLORS[i % COLORS.length], width: 2 },
    marker: { size: 6 },
  }));
  Plotly.newPlot(div2, traces2, mkLayout('Error Rate (%) vs Concurrency', 'Concurrent Clients', 'Error Rate %'), { responsive: true });
}

// ── Init ──
buildControls();
render();
</script>
</body>
</html>"""


def generate_html(data: dict, output_path: str) -> None:
    """Generate self-contained HTML dashboard."""
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    data_json = json.dumps(data, separators=(",", ":"))
    content = HTML_TEMPLATE.replace("__DATA_PLACEHOLDER__", data_json)
    with open(output_path, "w") as f:
        f.write(content)
    print(f"Dashboard written to: {output_path}")
    size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"File size: {size_mb:.1f} MB")


def main():
    parser = argparse.ArgumentParser(description="Generate AIPerf benchmark dashboard")
    parser.add_argument("dir", help="Path to models/, a benchmark/ dir, or an e2e timestamp dir")
    parser.add_argument("--output", "-o", default=None, help="Output HTML path (default: <dir>/benchmark-dashboard.html)")
    parser.add_argument("--open", action="store_true", help="Open in browser after generating")
    parser.add_argument("--max-requests", type=int, default=300, help="Max per-request rows to include per run (default: 300)")
    args = parser.parse_args()

    target_dir = args.dir
    if not os.path.isdir(target_dir):
        print(f"ERROR: {target_dir} is not a directory")
        sys.exit(1)

    print(f"Scanning {target_dir} for benchmark results...")
    runs = find_benchmark_runs(target_dir)
    if not runs:
        print("ERROR: No benchmark runs found")
        sys.exit(1)

    print(f"Found {len(runs)} benchmark runs across {len(set(r['model'] for r in runs))} model(s)")

    print("Loading data...")
    data = build_dashboard_data(runs)

    output_path = args.output or os.path.join(target_dir, "benchmark-dashboard.html")
    generate_html(data, output_path)

    if args.open:
        import webbrowser
        webbrowser.open("file://" + os.path.abspath(output_path))


if __name__ == "__main__":
    main()
