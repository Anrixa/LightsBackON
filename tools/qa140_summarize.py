#!/usr/bin/env python3
"""QA140: summarize a directory of QA56/QA140 runs pulled back from a remote Windows test PC.

Each run directory holds frames.csv (QA56 probe), frames_qa140.json (scenario driver), resources.csv (Windows
process counters) and done.json (target runner). For every run this prints nearest-rank P50/P95/P99/max frame
interval per scenario segment (first five seconds excluded, as qa56_analyze.py does), engine-reported video memory,
and Windows working-set / dedicated / shared GPU memory peaks, and writes summary.json + summary.md.
Frame intervals are Godot main-loop pacing, not display present timing. This is a measurement report, never a gate PASS.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

WARMUP_MS = 5000.0
MIB = 1024.0 * 1024.0


def rank(values: list[float], percent: float) -> float:
    ordered = sorted(values)
    return round(ordered[max(0, math.ceil(len(ordered) * percent) - 1)], 3)


def frame_stats(values: list[float]) -> dict[str, float | int]:
    if not values:
        return {"count": 0}
    return {
        "count": len(values),
        "p50_ms": rank(values, 0.50),
        "p95_ms": rank(values, 0.95),
        "p99_ms": rank(values, 0.99),
        "max_ms": round(max(values), 3),
        "over_16_7ms": sum(v > 16.7 for v in values),
        "over_33_3ms": sum(v > 33.3 for v in values),
    }


def peak_mib(rows: list[dict[str, str]], key: str) -> float | None:
    values = [float(r[key]) for r in rows if r.get(key, "").strip()]
    return round(max(values) / MIB, 1) if values else None


def summarize_run(run: Path) -> dict[str, object]:
    done = json.loads(run.joinpath("done.json").read_text(encoding="utf-8-sig"))
    out: dict[str, object] = {"label": run.name, "exit_code": done.get("exit_code"),
                              "timed_out": done.get("timed_out"), "error": done.get("error", "")}
    report_path = run / "frames_qa140.json"
    if report_path.exists():
        report = json.loads(report_path.read_text(encoding="utf-8"))
        out.update({k: report.get(k) for k in ("adapter_name", "adapter_api_version", "rendering_method",
                                                "rendering_driver", "viewport_size", "vsync_mode", "screen_refresh_hz")})
        out["steps"] = report.get("steps", [])
        out["engine_segments"] = {str(s["segment"]): s for s in report.get("segments", [])}
    frames_path = run / "frames.csv"
    by_segment: dict[str, list[float]] = {}
    overall: list[float] = []
    if frames_path.exists():
        with frames_path.open(newline="", encoding="utf-8-sig") as stream:
            for row in csv.DictReader(stream):
                if float(row["elapsed_ms"]) < WARMUP_MS:
                    continue
                value = float(row["frame_ms"])
                by_segment.setdefault(row["segment"], []).append(value)
                overall.append(value)
    out["frames_overall"] = frame_stats(overall)
    out["frames_by_segment"] = {k: frame_stats(v) for k, v in sorted(by_segment.items(), key=lambda i: int(i[0]))}
    resources_path = run / "resources.csv"
    if resources_path.exists():
        with resources_path.open(newline="", encoding="utf-8-sig") as stream:
            rows = list(csv.DictReader(stream))
        out["windows_samples"] = len(rows)
        out["working_set_peak_mib"] = peak_mib(rows, "working_set_bytes")
        out["private_peak_mib"] = peak_mib(rows, "private_bytes")
        out["gpu_dedicated_peak_mib"] = peak_mib(rows, "gpu_dedicated_bytes")
        out["gpu_shared_peak_mib"] = peak_mib(rows, "gpu_shared_bytes")
        tail = [float(r["working_set_bytes"]) for r in rows[-10:]]
        head = [float(r["working_set_bytes"]) for r in rows[len(rows) // 3: len(rows) // 3 + 10]]
        if head and tail:
            out["working_set_late_minus_mid_mib"] = round((sum(tail) / len(tail) - sum(head) / len(head)) / MIB, 1)
    return out


def markdown(runs: list[dict[str, object]]) -> str:
    names = ["menu_idle", "mission_idle", "walk_look", "tablet_toggle", "pause_toggle", "final_idle"]
    lines = ["| Run | Adapter / renderer | Viewport | Overall P50 / P95 / P99 / max ms | Mission P95 (idle / walk / tablet / pause) ms "
             "| >33.3 ms frames | Engine video MiB | WS peak MiB | GPU dedicated / shared peak MiB |",
             "|---|---|---|---|---|---|---|---|---|"]
    for r in runs:
        fo = r.get("frames_overall", {})
        seg = r.get("frames_by_segment", {})
        eng = r.get("engine_segments", {})
        video = max((int(s.get("video_mem_peak_bytes", 0)) for s in eng.values()), default=0) / MIB
        mission = " / ".join(str(seg.get(str(i), {}).get("p95_ms", "?")) for i in (1, 2, 3, 4))
        overall = (f"{fo.get('p50_ms', '?')} / {fo.get('p95_ms', '?')} / {fo.get('p99_ms', '?')} / {fo.get('max_ms', '?')}"
                   if fo.get("count") else "no frames")
        vp = r.get("viewport_size") or ["?", "?"]
        vs = "vsync on" if r.get("vsync_mode") == 1 else "vsync off"
        lines.append(f"| {r['label']} | {r.get('adapter_name', '?')} / {r.get('rendering_method', '?')} ({vs}) | "
                     f"{vp[0]}x{vp[1]} | {overall} | {mission} | {fo.get('over_33_3ms', '?')} | {video:.1f} | "
                     f"{r.get('working_set_peak_mib')} | {r.get('gpu_dedicated_peak_mib')} / {r.get('gpu_shared_peak_mib')} |")
    lines.append("")
    lines.append("Segments: " + ", ".join(f"{i} = {n}" for i, n in enumerate(names)) + ". First 5 s of each run excluded.")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path, help="directory with one subdirectory per run")
    args = parser.parse_args()
    runs = [summarize_run(p) for p in sorted(args.results.iterdir()) if p.joinpath("done.json").exists()]
    args.results.joinpath("summary.json").write_text(json.dumps(runs, indent=2) + "\n", encoding="utf-8")
    table = markdown(runs)
    args.results.joinpath("summary.md").write_text(table, encoding="utf-8")
    print(table)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
