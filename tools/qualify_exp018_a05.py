#!/usr/bin/env python3
"""EXP018 A05 independent source auditor and exact-head Godot replay verifier.

Preflight checks original dispatch identities; post-run checks actual evidence
written by the Godot test suite, without mistaking case-machine solves for full
MissionDirector completion. CI must still check the Godot exit status.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
if __package__:
    from . import qualify_exp018_a04 as a04
    from . import qualify_exp015_integration as original
else:
    import qualify_exp018_a04 as a04
    import qualify_exp015_integration as original
ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=ROOT/"build/exp018-a05/host-replay-evidence.json"

def sources(root:Path=ROOT)->dict:
    if root.resolve()!=ROOT.resolve():
        raise ValueError("EXP018_A05_ROOT_MISMATCH")
    inherited=a04.qualify(root)
    atlas,network=original.load_sources(root)
    verified=original.audit_original_regions(atlas,network)
    if any(verified[k]!=n for k,n in (
        ("regions",25),("authored_levels",200),("source_task_ids",1000))):
        raise ValueError("EXP018_A05_SOURCE_IDENTITY_DRIFT")
    if not (root/"tests/integration/test_EXP018_A05_all_host_replays.gd").is_file():
        raise ValueError("EXP018_A05_GODOT_SUITE_MISSING")
    return {
        "phase":"EXP018_A05",
        "original_regions":25,"original_levels":200,"original_task_ids":1000,
        "casework_headless_replay":"GODOT_EXECUTION_REQUIRED",
        "actual_all_200_mission_completion":"NOT_ESTABLISHED",
        "linux_windows":"EXTERNAL_EXACT_HEAD_CI_REQUIRED",
        "release_holds":"PRESERVED", "ready_for_merge":False,
        "ready_for_release":False,
        "inherited_visual_source":inherited["visual_policy"]
    }

def post_run(root:Path=ROOT)->dict:
    if not EVIDENCE.is_file():
        raise ValueError("EXP018_A05_GODOT_REPLAY_EVIDENCE_MISSING")
    data=json.loads(EVIDENCE.read_text(encoding="utf-8"))
    if data.get("phase")!="EXP018_A05" or data.get("status")!="PASS":
        raise ValueError("EXP018_A05_GODOT_REPLAY_FAILED")
    for name,count in (
        ("level_count",200),("source_task_id_count",1000),
        ("host_inspect_accepted_count",200),
        ("host_duplicate_idempotent_count",200),
        ("nonlinear_source_route_count",400),
        ("adverse_recovery_route_count",25)):
        if data.get(name)!=count:
            raise ValueError(f"EXP018_A05_REPLAY_CARDINALITY_DRIFT: {name}")
    if data.get("full_authoritative_mission_completion")!="NOT_ESTABLISHED":
        raise ValueError("EXP018_A05_UNSUPPORTED_RELEASE_CLAIM")
    atlas,net=original.load_sources(root)
    original.audit_original_regions(atlas,net)
    records=data.get("records",[])
    if not isinstance(records,list) or len(records)!=200:
        raise ValueError("EXP018_A05_PER_LEVEL_EVIDENCE_MISSING")
    expected_ids=set()
    for i,record in enumerate(records):
        level=atlas["levels"][i]
        id=f"LV_{i+1:03d}"
        tasks=[t["id"] for t in level["tasks"]]
        if (record.get("level_id")!=id or record.get("task_ids")!=tasks or
            not record.get("host_inspect_accepted") or
            not record.get("host_duplicate_idempotent") or
            record.get("source_case_routes_qualified")!=["priority","resilience"] or
            not str(record.get("host_source_revision","")).startswith("EXP016_")):
            raise ValueError("EXP018_A05_HOST_SOURCE_ORACLE_MISMATCH: "+id)
        expected_ids.update(tasks)
    if len(expected_ids)!=1000:
        raise ValueError("EXP018_A05_TASK_DUPLICATE_OR_MISSING")
    return {
        "phase":"EXP018_A05",
        "status":"ACTUAL_GODOT_HOST_SOURCE_REPLAY_EVIDENCED",
        "sha256":hashlib.sha256(EVIDENCE.read_bytes()).hexdigest(),
        "levels":len(records),"tasks":len(expected_ids),
        "host_commands":200,"adversarial_duplicate_checks":200,
        "nonlinear_completed_case_routes":400,
        "injected_failure_and_recovery_routes":25,
        "qualified_scope":"HEADLESS_HOST_ENVELOPES_AND_CASE_MACHINES_ONLY",
        "full_mission_director_completion":"HOLD",
        "human_physical_hardware_steam_save_release":"HOLD",
        "ready_for_release":False
    }

def main()->int:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--post-run",action="store_true")
    p.add_argument("--report",type=Path,default=Path("build/exp018-a05/source-preflight.json"))
    a=p.parse_args()
    try:
        result=post_run() if a.post_run else sources()
        a.report.parent.mkdir(parents=True,exist_ok=True)
        a.report.write_text(json.dumps(result,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    except (ValueError,TypeError,KeyError,OSError,AttributeError) as exc:
        print("[FAIL][EXP018_A05] "+str(exc),flush=True)
        return 1
    print("[PASS][EXP018_A05] "+("independent Godot evidence" if a.post_run else
          "25/200/1000 original source preflight"),flush=True)
    print("[HOLD][EXP018_A05] full MissionDirector replay/physical/Steam/release not certified; "+str(a.report),flush=True)
    return 0
if __name__=="__main__":
    raise SystemExit(main())
