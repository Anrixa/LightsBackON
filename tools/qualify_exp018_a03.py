#!/usr/bin/env python3
"""EXP018 A03: source-level composite revision and authorized-runtime gate."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
if __package__:
    from . import qualify_exp018_a02 as a02
else:
    import qualify_exp018_a02 as a02
ROOT = Path(__file__).resolve().parents[1]
HOST = ROOT / "scripts/gameplay/expedition_host_session.gd"
GODOT = ROOT / "tests/integration/test_EXP018_A03_joint_runtime.gd"

def qualify(root: Path = ROOT) -> dict:
    if root.resolve() != ROOT.resolve():
        raise ValueError("EXP018_A03_ROOT_MISMATCH")
    preflight=a02.qualify(root)
    host=HOST.read_text(encoding="utf-8")
    suite=GODOT.read_text(encoding="utf-8")
    for fragment in (
        "func start_exp018_authenticated_finale(", "EXP018_A03_ORIGINAL_FINALE_REQUIRED",
        "EXP018_A03_AUTHENTICATED_PROFILE_REQUIRED", '"EXP018_A03_"',
        '"exp018_advanced_cases"', '"exp018_advanced_cascade"',
        "EXP015_A12_9_STALE_HOST_DISPATCH",
        "advanced_cascade.record_host_completion(",
    ):
        if fragment not in host:
            raise ValueError("EXP018_A03_MISSING_AUTHORITY_BINDING: "+fragment)
    for fragment in (
        "test_EXP018_A03_25_region_finales_bind_original_resources_and_new_cases",
        "test_EXP018_A03_opt_in_fences_unauthenticated_or_nonfinale_requests",
        "EXP015_A12_15_STALE_REPLAY", "supply_before - 2",
    ):
        if fragment not in suite:
            raise ValueError("EXP018_A03_GODOT_REPLAY_MISSING: "+fragment)
    return {"phase":"EXP018_A03", "source_regions":preflight["region_count"],
            "source_levels":preflight["level_count"],
            "source_tasks":preflight["task_count"],
            "source_binding":"PASS",
            "exact_head_linux_windows_execution":"EXTERNAL_CI_REQUIRED",
            "physical_controller_steam":"HOLD", "production_economy_saves":"HOLD",
            "ready_for_merge":False,"ready_for_release":False}

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report",type=Path,default=Path("build/exp018-a03/qualification.json"))
    args=parser.parse_args()
    try:
        out=qualify()
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(out,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    except (OSError,ValueError,TypeError,KeyError) as exc:
        print("[FAIL][EXP018_A03] "+str(exc),flush=True)
        return 1
    print("[PASS][EXP018_A03] composite source/host regression present",flush=True)
    print("[HOLD][EXP018_A03] actual Linux/Windows host replay and external gates; report="+str(args.report),flush=True)
    return 0
if __name__=="__main__":
    raise SystemExit(main())
