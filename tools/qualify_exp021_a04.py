#!/usr/bin/env python3
"""EXP021 A04 fail-closed independent scene budget + simulated host stress gate.

Headless submission proxies are never reported as actual GPU draw calls,
p95 FPS, VRAM usage, physical path reachability or Steam networking.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "build/exp021-a04/headless-performance.json"


def verify(post: bool) -> dict:
    atlas = json.loads((ROOT / "scenes/expeditions/atlas.json").read_text(encoding="utf-8"))
    if len(atlas["levels"]) != 200 or len(atlas["regions"]) != 25:
        raise ValueError("EXP021_A04_ORIGINAL_ATLAS_DRIFT")
    ids = {task["id"] for level in atlas["levels"] for task in level["tasks"]}
    if len(ids) != 1000:
        raise ValueError("EXP021_A04_TASK_ID_DRIFT")
    required = (
        "scripts/world/exp021_render_batch.gd",
        "scripts/world/exp021_environment_art.gd",
        "tests/integration/test_EXP021_A04_optimizer_stress.gd",
    )
    if any(not (ROOT / path).is_file() for path in required):
        raise ValueError("EXP021_A04_SOURCE_OR_TEST_MISSING")
    result = {"phase": "EXP021_A04", "status": "SOURCE_PREFLIGHT_PASS",
              "regions": 25, "levels": 200, "task_ids": len(ids),
              "qualification": "HEADLESS_SOURCE_ONLY", "gpu_p95": "HOLD",
              "physical": "HOLD", "two_peer_steam": "HOLD", "release": "HOLD"}
    if not post:
        return result
    if not EVIDENCE.is_file():
        raise ValueError("EXP021_A04_GODOT_RUNTIME_EVIDENCE_MISSING")
    payload = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    expected = {
        "phase": "EXP021_A04", "status": "PASS",
        "sampled_regions": 25,
        "authenticated_host_inspects": 25,
        "idempotent_duplicate_replays": 400,
        "wrong_peer_denials": 200,
        "actual_gpu_p95": "NOT_MEASURED",
        "real_steam_network": "NOT_TESTED",
        "full_200_3d_physical_playability": "NOT_ESTABLISHED",
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            raise ValueError(f"EXP021_A04_EVIDENCE_MISMATCH:{key}")
    reports = payload.get("reports", [])
    if not isinstance(reports, list) or len(reports) != 25:
        raise ValueError("EXP021_A04_REGION_RECORDS_MISSING")
    for i, report in enumerate(reports):
        if report.get("level_id") != f"LV_{i * 8 + 1:03d}" or \
           report.get("region_id") != f"REG_{i + 1:02d}" or \
           report.get("source_task_count") != 5 or \
           report.get("source_meshes", 0) < 12 or \
           report.get("batched_submissions", 100) > 4 or \
           not report.get("accepted_host_inspect") or \
           report.get("duplicate_copies") != 16 or \
           report.get("unknown_peer_denials") != 8:
            raise ValueError(f"EXP021_A04_BAD_REGION_SAMPLE:{i}")
    result["status"] = "HEADLESS_STRESS_PASS_GPU_AND_STEAM_HOLD"
    result["headless_submission_proxy_saved"] = payload.get("mesh_submissions_saved_proxy")
    result["observed_host_stress_us"] = payload.get("host_stress_elapsed_us_observation_only")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--post-run", action="store_true")
    parser.add_argument("--report", type=Path, default=Path("build/exp021-a04/source-gate.json"))
    args = parser.parse_args()
    try:
        outcome = verify(args.post_run)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(outcome, sort_keys=True, indent=2) + "\n",
                               encoding="utf-8")
    except (ValueError, KeyError, TypeError, OSError) as exc:
        print(f"[FAIL][EXP021_A04] {exc}", flush=True)
        return 1
    print(f"[PASS][EXP021_A04] {outcome['status']}", flush=True)
    print("[HOLD] GPU p95, memory, real Steam, actual traversal and release",
          flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
