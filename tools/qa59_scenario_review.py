#!/usr/bin/env python3
"""QA59: scenario-level review of four source-pinned Windows capture packages.

QA58 establishes package integrity and same-build repeatability. This module
adds per-F9-scenario frame pacing, per-scene breakdown and strict fixed-viewport
checks; it never turns synthetic/self-reported data into hardware acceptance.
All inputs and outputs remain local. No network or player identifiers are used.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
from typing import Any

from tools.qa56_analyze import percentile
from tools.qa57_integrity import STAGES, read_csv, sha256_file
from tools.qa58_compare import RESOLUTIONS, compare, load_capture

SCENARIO_NAMES = {
    0: "initial_menu",
    1: "first_repair",
    2: "tablet_operations",
    3: "pause_and_accessibility",
    4: "return_to_menu",
}
FRAME_P95_TRIAGE_MS = 33.3


def _finite_positive(raw: str, label: str) -> float:
    """Reject bad numbers before they can affect sorting or percentile ranks."""
    try:
        value = float(raw)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"QA59 invalid {label}") from exc
    if not math.isfinite(value) or value <= 0.0:
        raise ValueError(f"QA59 invalid {label}")
    return value


def scenario_frames(
    frames: list[dict[str, str]], resolution: str
) -> dict[str, dict[str, Any]]:
    """Compute frame timing from raw F9 labels, without trusting report JSON.

    The five-second warm-up is excluded as in QA56. An all-frame fixed
    viewport is stricter than QA58's 95% dominant-dimension preflight.
    """
    expected_size = RESOLUTIONS.get(resolution)
    if expected_size is None:
        raise ValueError("QA59 unsupported resolution")

    by_stage: dict[int, list[tuple[float, float, str]]] = defaultdict(list)
    previous_ms = -1.0
    previous_stage = 0
    for row in frames:
        timestamp_ms = _finite_positive(row["elapsed_ms"], "frame timestamp")
        duration_ms = _finite_positive(row["frame_ms"], "frame interval")
        if timestamp_ms <= previous_ms:
            raise ValueError("QA59 frame timestamps are not increasing")
        previous_ms = timestamp_ms

        marker = row["segment"]
        if not marker.isdecimal() or int(marker) not in STAGES:
            raise ValueError("QA59 unexpected F9 segment")
        stage = int(marker)
        if stage < previous_stage:
            raise ValueError("QA59 F9 markers regress")
        previous_stage = stage

        if timestamp_ms < 5000:
            continue
        try:
            observed_size = (int(row["viewport_w"]), int(row["viewport_h"]))
        except (TypeError, ValueError, KeyError) as exc:
            raise ValueError("QA59 missing viewport measurement") from exc
        if observed_size != expected_size:
            raise ValueError("QA59 viewport changed or was not the requested fixed size")
        scene = row["scene"]
        if scene not in {"MainMenu", "MissionRoot", "Other", "Transition"}:
            raise ValueError("QA59 unsupported scene label")
        by_stage[stage].append((timestamp_ms, duration_ms, scene))

    output: dict[str, dict[str, Any]] = {}
    for stage, (expected_scene, required_s) in STAGES.items():
        rows = by_stage.get(stage, [])
        if len(rows) < 60:
            raise ValueError(f"QA59 scenario {stage} has insufficient frames")
        span_s = (rows[-1][0] - rows[0][0]) / 1000.0
        if span_s < required_s:
            raise ValueError(f"QA59 scenario {stage} is too short")
        correct_scene = sum(scene == expected_scene for _, _, scene in rows)
        if correct_scene / len(rows) < 0.75:
            raise ValueError(f"QA59 scenario {stage} has incorrect scene coverage")
        intervals = [duration for _, duration, _ in rows]
        scenes: dict[str, list[float]] = defaultdict(list)
        for _, duration, scene in rows:
            scenes[scene].append(duration)
        output[str(stage)] = {
            "scenario": SCENARIO_NAMES[stage],
            "expected_scene": expected_scene,
            "frame_count": len(intervals),
            "observed_span_s": round(span_s, 3),
            "expected_scene_fraction": round(correct_scene / len(rows), 5),
            "frame_p95_ms": percentile(intervals, 0.95),
            "frame_p99_ms": percentile(intervals, 0.99),
            "frame_max_ms": round(max(intervals), 3),
            "over_33_3ms_fraction": round(
                sum(ms > FRAME_P95_TRIAGE_MS for ms in intervals) / len(intervals), 5
            ),
            "scenes": {
                name: {
                    "frame_count": len(values),
                    "frame_p95_ms": percentile(values, 0.95),
                    "frame_p99_ms": percentile(values, 0.99),
                    "frame_max_ms": round(max(values), 3),
                }
                for name, values in sorted(scenes.items())
            },
        }
    return output


def load_scenario_capture(directory: Path) -> dict[str, Any]:
    """Reject changed files rather than extracting metrics from unchecked rows."""
    frame_path = directory / "frames.csv"
    before = sha256_file(frame_path)
    capture = load_capture(directory)  # QA56 + QA57 hashes/boot + QA58 dimensions
    frames = read_csv(
        frame_path,
        {"elapsed_ms", "frame_ms", "scene", "segment", "viewport_w", "viewport_h"},
    )
    if sha256_file(frame_path) != before:
        raise ValueError("QA59 frames changed during validation")
    capture["stage_metrics"] = scenario_frames(frames, capture["resolution"])
    return capture


def compare_scenarios(captures: list[dict[str, Any]]) -> dict[str, Any]:
    """Preserve every QA58 gate; stage metrics add triage, never release PASS."""
    baseline = compare(captures)
    failures: list[str] = list(baseline["failures"])
    triggers: list[str] = list(baseline["review_triggers"])
    resolution_pairs: dict[str, Any] = {}

    for resolution in RESOLUTIONS:
        pair = [run for run in captures if run.get("resolution") == resolution]
        if len(pair) != 2:
            continue  # Already rejected by the QA58 comparison.
        stage_comparisons: dict[str, Any] = {}
        for stage, name in SCENARIO_NAMES.items():
            stage_key = str(stage)
            rows = [run.get("stage_metrics", {}).get(stage_key) for run in pair]
            if any(row is None for row in rows):
                failures.append(f"{resolution} scenario {stage} has no metrics")
                continue
            first, second = rows
            assert first is not None and second is not None
            p95 = [first["frame_p95_ms"], second["frame_p95_ms"]]
            if max(p95) > FRAME_P95_TRIAGE_MS:
                triggers.append(
                    f"{resolution} scenario {stage} engine-loop P95 exceeds "
                    f"{FRAME_P95_TRIAGE_MS:g} ms; inspect rendered footage"
                )
            stage_comparisons[stage_key] = {
                "scenario": name,
                "run_1": first,
                "run_2": second,
                "run_2_minus_run_1_p95_ms": round(p95[1] - p95[0], 3),
            }
        resolution_pairs[resolution] = {"scenarios": stage_comparisons}

    return {
        "schema_version": 1,
        "kind": "QA59_SCENARIO_LEVEL_WINDOWS_REVIEW",
        "status": "COMPLETE_FOR_MANUAL_REVIEW" if not failures else "INCOMPLETE",
        "qa58_status": baseline["status"],
        "release_gate": "PENDING_PHYSICAL_AND_HUMAN_REVIEW",
        "captures_checked": len(captures),
        "resolution_pairs": resolution_pairs,
        "failures": failures,
        "review_triggers": triggers,
        "evidence_limitations": [
            "Capture self-consistency does not authenticate the device or operator.",
            "F9 labels do not prove repair, tablet, pause or controller actions.",
            "Stage frame timing is Godot engine-loop timing, not display presentation.",
            "Memory counters are compared across complete runs by QA58; independent "
            "Windows/Godot clocks prevent reliable per-stage RAM/VRAM attribution.",
            "Fixed Godot viewport does not prove monitor output resolution.",
            "A complete report is for human review only: UX01, V09, GPU, "
            "Steam and release gates remain unresolved.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--capture", type=Path, action="append", required=True,
        help="Four QA56/QA57 capture directories, two per viewport resolution",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    failures: list[str] = []
    captures: list[dict[str, Any]] = []
    for index, directory in enumerate(args.capture, start=1):
        try:
            captures.append(load_scenario_capture(directory))
        except (OSError, ValueError, KeyError, TypeError) as exc:
            # Deliberately exclude filesystem paths and personal file contents.
            failures.append(f"capture {index}: invalid evidence ({type(exc).__name__})")
    report = compare_scenarios(captures)
    report["failures"] = failures + report["failures"]
    if report["failures"]:
        report["status"] = "INCOMPLETE"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(
        f"QA59_SCENARIO_REVIEW={report['status']} "
        f"failures={len(report['failures'])} "
        f"review_triggers={len(report['review_triggers'])}"
    )
    return 0 if not report["failures"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
