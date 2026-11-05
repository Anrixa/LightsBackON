#!/usr/bin/env python3
"""QA56: report observed exported-build frame intervals and Windows process memory.

Frame intervals are Godot main-loop pacing, not GPU PresentMon or input latency.
Process GPU counters may be unavailable; missing values are never treated as zero.
There is deliberately no automatic release PASS from captured telemetry alone.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from statistics import median


def percentile(values: list[float], percent: float) -> float:
    if not values:
        raise ValueError("no samples")
    if not 0.0 < percent <= 1.0:
        raise ValueError("percentile must be in (0, 1]")
    ordered = sorted(values)
    return round(ordered[max(0, math.ceil(len(ordered) * percent) - 1)], 3)


def read_csv(path: Path, fields: set[str]) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames or not fields.issubset(set(reader.fieldnames)):
            raise ValueError(f"{path.name}: missing required CSV fields: {sorted(fields)}")
        return list(reader)


def _number(value: str, label: str) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"bad {label}") from exc
    if not math.isfinite(result):
        raise ValueError(f"nonfinite {label}")
    return result


def analyze(frames: list[dict[str, str]],
            memory: list[dict[str, str]]) -> dict[str, object]:
    if not frames or not memory:
        raise ValueError("both frame and process resource samples are required")
    grouped: dict[str, list[float]] = {}
    intervals: list[float] = []
    last_frame_t = -1.0
    for row in frames:
        t = _number(row["elapsed_ms"], "elapsed_ms")
        delta = _number(row["frame_ms"], "frame_ms")
        if t <= last_frame_t or delta <= 0:
            raise ValueError("frame times must be strictly increasing and positive")
        last_frame_t = t
        if t < 5000.0:  # Warm-up exclusion is explicit, not silently discarded.
            continue
        name = row["scene"]
        if name not in ("MainMenu", "MissionRoot", "Other", "Transition"):
            raise ValueError("unexpected scene label")
        segment = row["segment"]
        if not segment.isdecimal():
            raise ValueError("bad segment")
        grouped.setdefault(name, []).append(delta)
        intervals.append(delta)
    if not intervals:
        raise ValueError("no frames after five-second warm-up")

    mem_samples: list[dict[str, float | None]] = []
    last_memory_t = -1.0
    for row in memory:
        t = _number(row["elapsed_s"], "elapsed_s")
        ram = _number(row["working_set_bytes"], "working_set_bytes")
        private = _number(row["private_bytes"], "private_bytes")
        gpu_str = row["gpu_dedicated_bytes"].strip()
        gpu = _number(gpu_str, "gpu_dedicated_bytes") if gpu_str else None
        if t <= last_memory_t or min(t, ram, private) < 0 or (gpu is not None and gpu < 0):
            raise ValueError("resource samples must be nonnegative and time ordered")
        last_memory_t = t
        mem_samples.append({"t": t, "ram": ram, "private": private, "gpu": gpu})

    def series(key: str) -> dict[str, object]:
        points = [(float(m["t"]), float(m[key])) for m in mem_samples if m[key] is not None]
        if not points:
            return {"available": False, "count": 0, "min_mib": None,
                    "peak_mib": None, "first_last_delta_mib": None}
        divisor = 1024.0 * 1024.0
        return {
            "available": True, "count": len(points),
            "min_mib": round(min(v for _, v in points) / divisor, 3),
            "peak_mib": round(max(v for _, v in points) / divisor, 3),
            "first_last_delta_mib": round((points[-1][1] - points[0][1]) / divisor, 3),
        }

    window_seconds = last_frame_t / 1000.0
    gpu_count = sum(m["gpu"] is not None for m in mem_samples)
    completeness = (window_seconds >= 120.0 and len(intervals) >= 1000
                    and len(mem_samples) >= 30 and gpu_count >= 20
                    and "MainMenu" in grouped and "MissionRoot" in grouped)
    return {
        "schema_version": 1,
        "release_gate": "PENDING_PHYSICAL_REVIEW",
        "capture_completeness": "COMPLETE_FOR_REVIEW" if completeness else "INCOMPLETE",
        "notes": [
            "Frame times are process-loop intervals, not display presentation or input latency.",
            "VRAM is Windows per-process dedicated GPU counter data, not engine-only RID counts.",
            "First five seconds of frame samples excluded. No automatic P0/P1, UX or Steam approval.",
        ],
        "duration_s": round(window_seconds, 3),
        "frame_count_post_warmup": len(intervals),
        "frame_p95_ms": percentile(intervals, 0.95),
        "frame_p99_ms": percentile(intervals, 0.99),
        "frame_max_ms": round(max(intervals), 3),
        "over_33_3ms_fraction": round(sum(v > 33.3 for v in intervals) / len(intervals), 5),
        "scenes": {
            name: {"count": len(values), "p95_ms": percentile(values, 0.95),
                   "max_ms": round(max(values), 3)}
            for name, values in sorted(grouped.items())
        },
        "windows_process_memory_samples": len(mem_samples),
        "ram_working_set": series("ram"),
        "ram_private": series("private"),
        "gpu_dedicated": series("gpu"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=Path, required=True)
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = analyze(
        read_csv(args.frames, {"elapsed_ms", "frame_ms", "scene", "segment"}),
        read_csv(args.resources, {
            "elapsed_s", "working_set_bytes", "private_bytes", "gpu_dedicated_bytes",
        }),
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                           encoding="utf-8")
    print(f"QA56_REPORT={args.output} status={report['capture_completeness']} "
          f"frame_p95_ms={report['frame_p95_ms']} "
          f"gpu_counter_available={report['gpu_dedicated']['available']}")
    return 0 if report["capture_completeness"] == "COMPLETE_FOR_REVIEW" else 2


if __name__ == "__main__":
    raise SystemExit(main())
