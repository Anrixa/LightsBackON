#!/usr/bin/env python3
"""EXP021 A05: independent 200-source/200-scene evidence with honest alpha holds.

The phase can pass source/headless construction and still withhold alpha
qualification pending EXP019 physical mechanics, EXP020 campaign, real GPU,
controller/human playability and qualified two-client Steam networking.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "build/exp021-a05/scene-host-evidence.json"
PREDECESSOR = ROOT / "build/exp021-a04/headless-performance.json"
EXP018 = ROOT / "build/exp018-a05/host-replay-evidence.json"

DEPENDENCIES = {
    "EXP019_CONSOLIDATED_PHYSICS": (
        "scripts/world/exp019_physical_worksite.gd",
        "scripts/world/exp019_environment_physics.gd",
        "scripts/world/exp019_spatial_tasks.gd",
        "scripts/gameplay/exp019_field_tools.gd",
        "scripts/gameplay/exp019_mechanical_pass.gd",
    ),
    "EXP020_CONSOLIDATED_CAMPAIGN_UX": (
        "scripts/gameplay/expedition_run_flow.gd",
        "scripts/gameplay/expedition_story_workorders.gd",
        "scripts/ui/expedition_field_ops.gd",
        "scripts/progression/expedition_reward_feedback.gd",
        "scripts/progression/expedition_campaign_consequences.gd",
    )
}

PHASE_SOURCE = (
    "scripts/world/exp021_environment_art.gd",
    "scripts/world/exp021_spatial_audio.gd",
    "scripts/world/exp021_restoration_effects.gd",
    "scripts/world/exp021_render_batch.gd",
    "tests/integration/test_EXP021_A05_alpha_candidate.gd",
    "tools/qualify_exp021_a04.py",
    "tools/qualify_exp021_a05.py",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_records() -> tuple[dict, list[dict]]:
    catalog = json.loads((ROOT / "scenes/expeditions/atlas.json").read_text(encoding="utf-8"))
    levels, locations, regions = (catalog.get("levels"), catalog.get("locations"),
                                 catalog.get("regions"))
    if not all(isinstance(x, list) for x in (levels, locations, regions)):
        raise ValueError("EXP021_A05_INVALID_ORIGINAL_ATLAS")
    if (len(levels), len(locations), len(regions)) != (200, 200, 25):
        raise ValueError("EXP021_A05_ORIGINAL_25_200_SOURCE_DRIFT")
    records: list[dict] = []
    seen: set[str] = set()
    for i, (level, location) in enumerate(zip(levels, locations), start=1):
        level_id, location_id = f"LV_{i:03d}", f"LOC_{i:03d}"
        region_id = f"REG_{(i - 1) // 8 + 1:02d}"
        tasks = level.get("tasks", [])
        expected_tasks = [f"JOB_{i:03d}_{j}" for j in range(1, 6)]
        actual_tasks = [x.get("id") for x in tasks]
        if (level.get("id") != level_id or location.get("id") != location_id or
            level.get("location_id") != location_id or
            level.get("region_id") != region_id or
            location.get("district_id") != region_id or actual_tasks != expected_tasks):
            raise ValueError(f"EXP021_A05_SOURCE_JOIN_MISMATCH:{level_id}")
        if set(actual_tasks) & seen:
            raise ValueError(f"EXP021_A05_DUPLICATE_TASK:{level_id}")
        seen.update(actual_tasks)
        records.append({
            "level_id": level_id,
            "region_id": region_id,
            "location_id": location_id,
            "original_task_ids": expected_tasks
        })
    if len(seen) != 1000:
        raise ValueError("EXP021_A05_TASK_COUNT_DRIFT")
    return catalog, records


def dependency_status() -> dict:
    return {
        name: {
            "status": "SOURCE_PRESENT_REQUIRES_INTEGRATED_RUNTIME_QUALIFICATION" if
                all((ROOT / file).is_file() for file in paths)
                else "HOLD_NOT_PRESENT_ON_THIS_BRANCH",
            "missing_paths": [f for f in paths if not (ROOT / f).is_file()]
        }
        for name, paths in DEPENDENCIES.items()
    }


def validate(preview_only: bool = False) -> dict:
    _, expected = source_records()
    missing = [p for p in PHASE_SOURCE if not (ROOT / p).is_file()]
    if missing:
        raise ValueError("EXP021_A05_MISSING_IMPLEMENTATION:" + ",".join(missing))
    findings: dict = {
        "phase": "EXP021_A05", "status": "SOURCE_PREFLIGHT_PASSED",
        "source_regions": 25, "source_levels": 200, "source_task_ids": 1000,
        "source_files_sha256": {path: sha256(ROOT / path) for path in PHASE_SOURCE},
        "dependencies": dependency_status(),
        "alpha_acceptance": "HOLD", "actual_full_mission_completions": "NOT_ESTABLISHED",
        "human_controller_real_gpu_steam": "NOT_TESTED",
        "ready_for_release": False
    }
    if preview_only:
        return findings
    if not REPORT.is_file():
        raise ValueError("EXP021_A05_GODOT_SCENE_HOST_REPORT_MISSING")
    if not PREDECESSOR.is_file() or not EXP018.is_file():
        raise ValueError("EXP021_A05_INHERITED_EXECUTION_EVIDENCE_MISSING")
    original = json.loads(EXP018.read_text(encoding="utf-8"))
    stress = json.loads(PREDECESSOR.read_text(encoding="utf-8"))
    if (original.get("status") != "PASS" or original.get("level_count") != 200 or
        original.get("source_task_id_count") != 1000 or
        original.get("nonlinear_source_route_count") != 400 or
        original.get("adverse_recovery_route_count") != 25 or
        original.get("full_authoritative_mission_completion") != "NOT_ESTABLISHED"):
        raise ValueError("EXP021_A05_ORIGINAL_HOST_400_REPLAY_NOT_QUALIFIED")
    if (stress.get("status") != "PASS" or stress.get("sampled_regions") != 25 or
        stress.get("idempotent_duplicate_replays") != 400 or
        stress.get("wrong_peer_denials") != 200):
        raise ValueError("EXP021_A05_A04_STRESS_GATE_FAILED")
    actual = json.loads(REPORT.read_text(encoding="utf-8"))
    required = {
        "phase": "EXP021_A05", "status": "PASS",
        "scene_builds": 200, "host_startups": 200, "source_projections": 200,
        "environment_batch_assemblies": 200, "regions": 25,
        "distinct_scenes": 200, "original_task_ids": 1000,
        "full_audio_fx_samples": 25,
        "actual_mission_director_completions": "NOT_ESTABLISHED",
        "real_gpu_p95": "NOT_MEASURED", "two_client_steam": "NOT_TESTED",
        "human_controller_review": "NOT_TESTED", "release": "HOLD"
    }
    for key, value in required.items():
        if actual.get(key) != value:
            raise ValueError(f"EXP021_A05_SOURCE_REPORT_MISMATCH:{key}:{actual.get(key)}")
    rows = actual.get("records")
    if not isinstance(rows, list) or len(rows) != 200:
        raise ValueError("EXP021_A05_PER_LEVEL_EVIDENCE_MISSING")
    for i, (exp, got) in enumerate(zip(expected, rows), start=1):
        if not isinstance(got, dict) or any(got.get(k) != v for k, v in exp.items()):
            raise ValueError(f"EXP021_A05_SCENE_ID_OR_JOB_MISMATCH:LV_{i:03d}")
        if not all(got.get(k) is True for k in (
                "physical_world_constructed", "host_session_started",
                "host_canonical_restoration_projected")):
            raise ValueError(f"EXP021_A05_MISSING_RUNNING_SCENE_OR_HOST:LV_{i:03d}")
        if not (1 <= got.get("decoration_batches", 100) <= 4):
            raise ValueError(f"EXP021_A05_BAD_RENDER_BATCH:LV_{i:03d}")
        if got.get("physical_playability_qualified") is not False or \
           got.get("mission_director_completed") is not False:
            raise ValueError(f"EXP021_A05_UNSUPPORTED_CERTIFICATION:LV_{i:03d}")
    findings.update({
        "status": "200_SCENE_HEADLESS_CANDIDATE_EVIDENCED_NOT_ALPHA_CERTIFIED",
        "godot_scene_report_sha256": sha256(REPORT),
        "inherited_exp018_host_replays_sha256": sha256(EXP018),
        "inherited_exp021_a04_stress_sha256": sha256(PREDECESSOR),
        "actual_scene_builds": 200, "actual_host_startups": 200,
        "real_host_source_route_replays": 400
    })
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight", action="store_true")
    parser.add_argument("--report", type=Path,
                        default=Path("build/exp021-a05/alpha-gate.json"))
    args = parser.parse_args()
    try:
        result = validate(preview_only=args.preflight)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    except (ValueError, OSError, TypeError, KeyError) as exc:
        print(f"[FAIL][EXP021_A05] {exc}", file=sys.stderr, flush=True)
        return 1
    print(f"[PASS][EXP021_A05] {result['status']}", flush=True)
    for phase, item in result["dependencies"].items():
        print(f"[DEPENDENCY][{phase}] {item['status']}", flush=True)
        for missing in item["missing_paths"]:
            print(f"  MISSING: {missing}", flush=True)
    print("[HOLD][EXP021_A05] True alpha/hardware/Steam/human/production/release",
          flush=True)
    print(f"[EVIDENCE] {args.report}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
