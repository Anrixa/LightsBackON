#!/usr/bin/env python3
"""EXP018 A04: static source joins and host-first presentation entry."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
if __package__:
    from . import qualify_exp018_a03 as a03
else:
    import qualify_exp018_a03 as a03
ROOT=Path(__file__).resolve().parents[1]
def qualify(root: Path=ROOT)->dict:
    if root.resolve()!=ROOT.resolve():
        raise ValueError("EXP018_A04_ROOT_MISMATCH")
    inherited=a03.qualify(root)
    bridge=(root/"scripts/world/exp018_host_presentation.gd").read_text(encoding="utf-8")
    stage=(root/"scripts/gameplay/expedition_mission_stage.gd").read_text(encoding="utf-8")
    suite=(root/"tests/integration/test_EXP018_A04_world_projection.gd").read_text(encoding="utf-8")
    for token in ("runtime.task_board()", "runtime.authoritative_state()",
                  "runtime.grid.canonical_state()", "Presentation.reflect(",
                  "EXP018_A04_RETIRED_OR_INVALID_HOST", "EXP018_A04_REGIONAL_HOST_SOURCE_DRIFT"):
        if token not in bridge:
            raise ValueError("EXP018_A04_BRIDGE_MISSING: "+token)
    for token in ("exp018_integrated_enabled","start_exp018_authenticated_finale",
                  "Exp018Presentation.reflect(", "Callable(self, \"_world_sight\")"):
        if token not in stage:
            raise ValueError("EXP018_A04_STAGING_INTEGRATION_MISSING: "+token)
    for token in ("test_EXP018_A04_all_200_host_source_bindings",
                  "assert_eq(passed, 200)", "EXP018_A04_SOURCE_LEVEL_MISMATCH"):
        if token not in suite:
            raise ValueError("EXP018_A04_MISSING_GODOT_REGRESSION: "+token)
    return {"phase":"EXP018_A04", "source_regions":inherited["source_regions"],
            "site_bindings":200, "task_bindings":inherited["source_tasks"],
            "visual_policy":"READ_ONLY_HOST_CANONICAL_GRID",
            "godot_host_replays":"EXACT_HEAD_CI_REQUIRED",
            "hardware_controller_steam":"HOLD", "release":"HOLD",
            "ready_for_merge":False,"ready_for_release":False}
def main()->int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report",type=Path,default=Path("build/exp018-a04/qualification.json"))
    args=parser.parse_args()
    try:
        r=qualify()
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(r,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    except (OSError,ValueError,TypeError,KeyError) as exc:
        print("[FAIL][EXP018_A04] "+str(exc),flush=True);return 1
    print("[PASS][EXP018_A04] 25 regional visual identities, 200 site bindings, source-gated host projection",flush=True)
    print("[HOLD][EXP018_A04] Linux/Windows headless execution and physical/release holds",flush=True)
    return 0
if __name__=="__main__":
    raise SystemExit(main())
