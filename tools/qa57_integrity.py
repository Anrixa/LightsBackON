#!/usr/bin/env python3
"""QA57: fail-closed provenance and workflow checks for an offline Windows capture.

This validates *self-consistency*, not whether a person used a controller,
whether the display actually presented frames, or whether a GPU is physical.
The outcome can only be COMPLETE_FOR_PHYSICAL_REVIEW, never release approval.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import re

HEX32 = re.compile(r"^[0-9a-f]{32}$")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")

# QA56's F9 scenario markers. A minimum elapsed span is required in each;
# markers are not proof of repeated interactions, controller use or screenshots.
STAGES = {
    0: ("MainMenu", 30.0),      # initial menu
    1: ("MissionRoot", 60.0),   # first repair path
    2: ("MissionRoot", 30.0),   # repeated tablet operations
    3: ("MissionRoot", 30.0),   # pause/accessibility operations
    4: ("MainMenu", 20.0),      # return to menu and quit
}
MIN_EXPECTED_SCENE_SHARE = 0.75


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as src:
        for chunk in iter(lambda: src.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_csv(path: Path, columns: set[str]) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as src:
        reader = csv.DictReader(src)
        if not reader.fieldnames or not columns.issubset(reader.fieldnames):
            raise ValueError(f"{path.name}: expected columns {sorted(columns)}")
        return list(reader)


def finite_nonnegative(raw: str, field: str) -> float:
    try:
        result = float(raw)
    except (ValueError, TypeError) as exc:
        raise ValueError(f"{field}: not numeric") from exc
    if not math.isfinite(result) or result < 0:
        raise ValueError(f"{field}: must be finite and nonnegative")
    return result


def assess(
    metadata: dict[str, object],
    frames: list[dict[str, str]],
    resources: list[dict[str, str]],
    summary: dict[str, object],
    *,
    frame_sha256: str,
    resource_sha256: str,
) -> dict[str, object]:
    """Return a bounded audit report instead of silently endorsing bad data."""
    problems: list[str] = []

    session_id = str(metadata.get("session_id", ""))
    if not HEX32.fullmatch(session_id):
        problems.append("session_id must be 32 lowercase hex characters")
    for key, pattern in (
        ("executable_sha256", HEX64), ("pack_sha256", HEX64),
        ("build_manifest_sha256", HEX64), ("git_commit", HEX40),
    ):
        if not pattern.fullmatch(str(metadata.get(key, ""))):
            problems.append(f"{key} is missing or malformed")

    if metadata.get("frame_csv_sha256") != frame_sha256:
        problems.append("frame CSV checksum mismatch")
    if metadata.get("resource_csv_sha256") != resource_sha256:
        problems.append("resource CSV checksum mismatch")
    if not isinstance(metadata.get("build_id"), str) or not metadata.get("build_id"):
        problems.append("build_id is missing")
    if not str(metadata.get("engine_version", "")).startswith("4.7.2."):
        problems.append("engine version is not pinned to Godot 4.7.2")
    if metadata.get("git_dirty") is not False:
        problems.append("manifest requires a clean source commit")

    if metadata.get("exited_naturally") is not True:
        problems.append("game did not exit naturally")
    if type(metadata.get("process_exit_code")) is not int or metadata["process_exit_code"] != 0:
        problems.append("game exit code must be exactly zero")
    if metadata.get("capture_timed_out") is not False:
        problems.append("capture was aborted or timed out")
    if summary.get("capture_completeness") != "COMPLETE_FOR_REVIEW":
        problems.append("base QA56 capture completeness gate failed")
    if summary.get("release_gate") != "PENDING_PHYSICAL_REVIEW":
        problems.append("base report must not assert release approval")

    # Samples must belong to one coherent process lifetime. This does not
    # authenticate the recording; it detects stale or truncated CSV pairings.
    if not frames or not resources:
        problems.append("frame and process data are both required")
    else:
        if metadata.get("process_samples") != len(resources):
            problems.append("process sample count differs from metadata")
        try:
            last_frame_s = finite_nonnegative(frames[-1]["elapsed_ms"], "elapsed_ms") / 1000.0
            last_memory_s = finite_nonnegative(resources[-1]["elapsed_s"], "elapsed_s")
            step = finite_nonnegative(str(metadata.get("sample_seconds")), "sample_seconds")
            tolerance = max(10.0, step * 2.0 + 5.0)
            if abs(last_frame_s - last_memory_s) > tolerance:
                problems.append("frame/process timelines diverge")
        except (KeyError, ValueError) as exc:
            problems.append(f"invalid capture timeline: {exc}")
        if not any(row.get("gpu_dedicated_bytes", "").strip() for row in resources):
            problems.append("dedicated GPU counter was not observed")

    # Each F9 marker has a monotonic expected ordinal. A contiguous sequence
    # alone is insufficient: verify meaningful duration and scene coverage.
    stage_samples: dict[int, list[tuple[float, str]]] = {}
    previous_segment = -1
    try:
        for row in frames:
            t = finite_nonnegative(row["elapsed_ms"], "elapsed_ms")
            raw_segment = row["segment"]
            if not raw_segment.isdecimal():
                raise ValueError("invalid F9 segment")
            marker = int(raw_segment)
            if marker < previous_segment or marker not in STAGES:
                raise ValueError("nonmonotonic or unsupported F9 segment")
            previous_segment = marker
            if t >= 5000.0:
                stage_samples.setdefault(marker, []).append((t, row["scene"]))
    except (KeyError, ValueError) as exc:
        problems.append(f"invalid scenario markers: {exc}")

    stages: dict[str, object] = {}
    for index, (scene, required_s) in STAGES.items():
        rows = stage_samples.get(index, [])
        span_s = round((rows[-1][0] - rows[0][0]) / 1000.0, 3) if len(rows) > 1 else 0.0
        coverage = (sum(label == scene for _, label in rows) / len(rows)) if rows else 0.0
        stages[str(index)] = {
            "expected_scene": scene, "frames": len(rows),
            "observed_span_s": span_s, "expected_scene_fraction": round(coverage, 3),
            "required_span_s": required_s,
        }
        if len(rows) < 60 or span_s < required_s:
            problems.append(f"scenario {index} lacks required frame duration")
        if coverage < MIN_EXPECTED_SCENE_SHARE:
            problems.append(f"scenario {index} has insufficient {scene} coverage")

    # Never emit private file paths, user identity, hardware serials or account
    # identifiers. Hashes are build provenance, not device fingerprints.
    return {
        "schema_version": 1,
        "kind": "QA57_CAPTURE_INTEGRITY",
        "status": "COMPLETE_FOR_PHYSICAL_REVIEW" if not problems else "INCOMPLETE",
        "release_gate": "PENDING_PHYSICAL_REVIEW",
        "evidence_limitations": [
            "Checks self-consistency only; files are not cryptographically signed.",
            "F9 stage presence does not prove actual tablet, accessibility or controller actions.",
            "Human visual/UX acceptance, real physical GPU and presentation timing remain unverified.",
        ],
        "stage_coverage": stages,
        "failures": problems,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--frames", type=Path, required=True)
    parser.add_argument("--resources", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    meta = json.loads(args.metadata.read_text(encoding="utf-8-sig"))
    base_report = json.loads(args.report.read_text(encoding="utf-8-sig"))
    result = assess(
        meta,
        read_csv(args.frames, {"elapsed_ms", "frame_ms", "scene", "segment"}),
        read_csv(args.resources, {
            "elapsed_s", "working_set_bytes", "private_bytes", "gpu_dedicated_bytes",
        }),
        base_report,
        frame_sha256=sha256_file(args.frames),
        resource_sha256=sha256_file(args.resources),
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"QA57_INTEGRITY={result['status']} failures={len(result['failures'])}")
    return 0 if not result["failures"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
