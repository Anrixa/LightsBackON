#!/usr/bin/env python3
"""EXP018 A02: joint ancestry, immutable-contract and registered suite audit."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
if __package__:
    from . import qualify_exp018_a01 as a01
else:
    import qualify_exp018_a01 as a01

ROOT = Path(__file__).resolve().parents[1]
ADVANCED = (
    "expedition_advanced_casework.gd",
    "expedition_advanced_fault_layers.gd",
    "expedition_advanced_hazards.gd",
    "expedition_advanced_equipment.gd",
    "expedition_advanced_policies.gd",
    "expedition_advanced_cascade.gd",
    "expedition_advanced_discoveries.gd",
)
VISUAL = ("exp017_region_identity.gd", "exp017_site_access.gd",
          "exp017_restoration_feedback.gd")

def qualify(root: Path = ROOT) -> dict:
    if root.resolve() != ROOT.resolve():
        raise ValueError("EXP018_A02_ROOT_MISMATCH")
    guarded = a01.qualify(root)
    host = (root / "scripts/gameplay/expedition_host_session.gd").read_text(encoding="utf-8")
    runner = (root / "tools/run_tests.sh").read_text(encoding="utf-8")
    for name in ADVANCED:
        if not (root / "scripts/gameplay" / name).is_file():
            raise ValueError("EXP018_A02_MISSING_EXP016_RUNTIME: " + name)
    for name in VISUAL:
        if not (root / "scripts/world" / name).is_file():
            raise ValueError("EXP018_A02_MISSING_EXP017_WORLD: " + name)
    for fragment in (
        "func _start_unchecked(", "func start_exp016_source_qualification(",
        "enable_anchor_recovery: bool = false,",
        "enable_advanced_cases: bool = false,",
        "EXP015_A12_9_", "EXP016_A02_CASEWORK_REQUIRED",
        "advanced_cases.definition_snapshot()",
    ):
        if fragment not in host:
            raise ValueError("EXP018_A02_MISSING_HOST_INTEGRATION: " + fragment)
    for phase in ("EXP015 A15", "EXP016 A12", "EXP018 A01"):
        if phase not in runner:
            raise ValueError("EXP018_A02_INHERITED_CI_SUITE_MISSING: " + phase)
    for name in (
        "test_EXP016_A12_full_replay.gd",
        "test_EXP017_A03_restoration_feedback.gd",
        "test_EXP015_A12_13_stale_snapshots.gd",
    ):
        if not (root / "tests/integration" / name).is_file():
            raise ValueError("EXP018_A02_CROSS_TRACK_TEST_MISSING: " + name)
    return {"phase":"EXP018_A02", "region_count":guarded["regional_source"]["regions"],
            "level_count":guarded["regional_source"]["authored_levels"],
            "task_count":guarded["regional_source"]["source_task_ids"],
            "protected_objects":guarded["protected_objects"],
            "exp016_runtime_modules":len(ADVANCED),
            "exp017_world_modules":len(VISUAL),
            "legacy_contracts": "PRESERVED",
            "composite_runtime_state": "NOT_YET_QUALIFIED_A03_A04",
            "ci_execution": "EXACT_HEAD_LINUX_AND_WINDOWS_EXTERNAL",
            "ready_for_merge":False, "ready_for_release":False}

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report",type=Path,default=Path("build/exp018-a02/qualification.json"))
    args=parser.parse_args()
    try:
        report=qualify()
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(report,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    except (ValueError,KeyError,OSError,TypeError) as exc:
        print("[FAIL][EXP018_A02] "+str(exc),flush=True)
        return 1
    print("[PASS][EXP018_A02] EXP015/EXP016/EXP017 source joins and protected source verified",flush=True)
    print("[HOLD][EXP018_A02] joint runtime and Windows CI pending; report="+str(args.report),flush=True)
    return 0

if __name__=="__main__":
    raise SystemExit(main())
