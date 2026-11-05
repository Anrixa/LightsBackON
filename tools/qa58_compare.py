#!/usr/bin/env python3
"""QA58: compare repeated opt-in Windows captures without asserting release approval.

Requires two independent fixed-viewport QA56/QA57 captures at 1280x720 and
two at 1920x1080 from the exact same exported build and GPU/driver.
Recomputes both existing reports from raw evidence rather than trusting
the supplied JSON. Human, monitor, controller and GPU provenance still
need independent review.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
from typing import Any

from tools.qa56_analyze import analyze
from tools.qa57_integrity import assess, read_csv, sha256_file

RESOLUTIONS = {"720p": (1280, 720), "1080p": (1920, 1080)}
REQUIRED_FILES = (
    "metadata.json", "frames.csv", "resources.csv", "report.json",
    "integrity.json", "godot.log",
)
MIN_DIMENSION_COVERAGE = 0.95


def read_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict):
        raise ValueError(f"{path.name}: expected JSON object")
    return data


def resolution_from_frames(frames: list[dict[str, str]]) -> tuple[str, float]:
    """Derive the dominant viewport from captured frames, not operator claims."""
    dimensions: Counter[tuple[int, int]] = Counter()
    for row in frames:
        if float(row["elapsed_ms"]) < 5000:
            continue
        try:
            width = int(row["viewport_w"])
            height = int(row["viewport_h"])
        except (KeyError, ValueError, TypeError) as exc:
            raise ValueError("QA58 viewport dimensions missing or invalid") from exc
        if width < 1 or height < 1:
            raise ValueError("QA58 viewport dimensions must be positive")
        dimensions[(width, height)] += 1
    if not dimensions:
        raise ValueError("QA58 no post-warmup viewport measurements")
    dominant, count = dimensions.most_common(1)[0]
    coverage = count / sum(dimensions.values())
    label = next(
        (name for name, size in RESOLUTIONS.items() if size == dominant),
        "unsupported",
    )
    if label == "unsupported" or coverage < MIN_DIMENSION_COVERAGE:
        raise ValueError(
            f"QA58 expected fixed 1280x720 or 1920x1080 viewport, "
            f"observed {dominant[0]}x{dominant[1]} for {coverage:.1%} of frames"
        )
    return label, round(coverage, 5)


def load_capture(directory: Path) -> dict[str, Any]:
    """Validate the exact raw package before accepting it into comparison."""
    if not directory.is_dir():
        raise ValueError("QA58 capture directory missing")
    missing = [name for name in REQUIRED_FILES if not (directory / name).is_file()]
    if missing:
        raise ValueError(f"QA58 capture is missing {', '.join(missing)}")

    meta = read_json(directory / "metadata.json")
    supplied_report = read_json(directory / "report.json")
    supplied_integrity = read_json(directory / "integrity.json")
    frames = read_csv(directory / "frames.csv", {
        "elapsed_ms", "frame_ms", "scene", "segment", "viewport_w", "viewport_h",
    })
    resources = read_csv(directory / "resources.csv", {
        "elapsed_s", "working_set_bytes", "private_bytes", "gpu_dedicated_bytes",
    })
    computed_report = analyze(frames, resources)
    if computed_report != supplied_report:
        raise ValueError("QA58 stored QA56 report differs from recalculated raw metrics")
    computed_integrity = assess(
        meta, frames, resources, supplied_report,
        frame_sha256=sha256_file(directory / "frames.csv"),
        resource_sha256=sha256_file(directory / "resources.csv"),
        boot_log_sha256=sha256_file(directory / "godot.log"),
        boot_log_text=(directory / "godot.log").read_text(
            encoding="utf-8-sig", errors="replace"
        ),
    )
    if supplied_integrity != computed_integrity:
        raise ValueError("QA58 stored QA57 integrity differs from recalculated integrity")
    if computed_integrity["status"] != "COMPLETE_FOR_PHYSICAL_REVIEW":
        raise ValueError("QA58 QA57 capture integrity did not pass")
    resolution, coverage = resolution_from_frames(frames)
    return {
        "resolution": resolution,
        "dimension_coverage": coverage,
        "session_id": meta["session_id"],
        "identity": {
            "git_commit": meta.get("git_commit"),
            "build_id": meta.get("build_id"),
            "executable_sha256": meta.get("executable_sha256"),
            "pack_sha256": meta.get("pack_sha256"),
            "build_manifest_sha256": meta.get("build_manifest_sha256"),
            "windows_version": meta.get("windows_version"),
            "video_controller_names": meta.get("video_controller_names"),
            "video_controller_driver_versions": meta.get("video_controller_driver_versions"),
        },
        "stats": computed_report,
    }


def compare(captures: list[dict[str, Any]]) -> dict[str, Any]:
    problems: list[str] = []
    warnings: list[str] = []
    grouped: dict[str, list[dict[str, Any]]] = {name: [] for name in RESOLUTIONS}

    if len(captures) != 4:
        problems.append("exactly four capture packages required (two per resolution)")
    sessions = [str(run.get("session_id", "")) for run in captures]
    if len(set(sessions)) != len(sessions):
        problems.append("capture session IDs must be distinct")
    if captures:
        identity = captures[0].get("identity")
        for run in captures[1:]:
            if run.get("identity") != identity:
                problems.append("source/export/GPU/driver/environment identity differs across captures")
                break
        if (not isinstance(identity, dict)
                or not identity.get("video_controller_names")
                or not identity.get("video_controller_driver_versions")):
            problems.append("observed Windows video controller and driver data required")

    for capture in captures:
        label = str(capture.get("resolution", ""))
        if label not in grouped:
            problems.append("unsupported capture resolution")
        else:
            grouped[label].append(capture)

    comparisons: dict[str, Any] = {}
    for label, runs in grouped.items():
        if len(runs) != 2:
            problems.append(f"{label} requires exactly two independent captures")
            continue
        first, second = runs
        memory: dict[str, Any] = {}
        for key in ("ram_working_set", "ram_private", "gpu_dedicated"):
            left, right = first["stats"][key], second["stats"][key]
            if not (left["available"] and right["available"]):
                problems.append(f"{label} missing {key} samples")
                continue
            difference = round(right["peak_mib"] - left["peak_mib"], 3)
            memory[key] = {
                "run_1_peak_mib": left["peak_mib"],
                "run_2_peak_mib": right["peak_mib"],
                "run_2_minus_run_1_peak_mib": difference,
                "run_1_first_last_delta_mib": left["first_last_delta_mib"],
                "run_2_first_last_delta_mib": right["first_last_delta_mib"],
            }
            # Triage thresholds only, not actual release budgets or proof of leaks.
            trigger = 128.0 if key == "gpu_dedicated" else 64.0
            if abs(difference) >= trigger:
                warnings.append(
                    f"{label} {key} peak differs by at least {trigger:g} MiB; inspect traces"
                )
        frame_p95 = [first["stats"]["frame_p95_ms"], second["stats"]["frame_p95_ms"]]
        if max(frame_p95) > 33.3:
            warnings.append(
                f"{label} an engine-loop P95 exceeds 33.3 ms; inspect scene and stalls"
            )
        comparisons[label] = {
            "frame_p95_ms": frame_p95,
            "frame_p99_ms": [first["stats"]["frame_p99_ms"], second["stats"]["frame_p99_ms"]],
            "frame_max_ms": [first["stats"]["frame_max_ms"], second["stats"]["frame_max_ms"]],
            "viewport_coverage": [first["dimension_coverage"], second["dimension_coverage"]],
            "memory": memory,
        }

    return {
        "schema_version": 1,
        "kind": "QA58_REPEATED_WINDOWS_CAPTURE_COMPARISON",
        "status": "COMPLETE_FOR_MANUAL_REVIEW" if not problems else "INCOMPLETE",
        "release_gate": "PENDING_PHYSICAL_AND_HUMAN_REVIEW",
        "captures_checked": len(captures),
        "comparisons": comparisons,
        "failures": problems,
        "review_triggers": warnings,
        "evidence_limitations": [
            "Self-consistent recordings cannot establish actual physical GPU use or human operation.",
            "Observed viewport is not verified monitor output or present-to-present timing.",
            "Two runs per resolution cannot prove leak absence or thermal stability.",
            "Screenshots, controller-only UX01, first repair, restoration and owner visual review remain required.",
            "No Steam, V09, accessibility or release qualification is granted.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--capture", type=Path, action="append", required=True,
        help="QA56/QA57 output directory (exactly four)"
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    problems: list[str] = []
    runs: list[dict[str, Any]] = []
    for index, directory in enumerate(args.capture, 1):
        try:
            runs.append(load_capture(directory))
        except (OSError, ValueError, KeyError, TypeError) as exc:
            # Never print absolute local paths or raw evidence contents.
            problems.append(
                f"capture {index}: {type(exc).__name__}: {str(exc).split(':', 1)[0]}"
            )
    result = compare(runs)
    if problems:
        result["failures"] = problems + result["failures"]
        result["status"] = "INCOMPLETE"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(
        f"QA58_COMPARISON={result['status']} failures={len(result['failures'])} "
        f"review_triggers={len(result['review_triggers'])}"
    )
    return 0 if not result["failures"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
