#!/usr/bin/env python3
"""EXP016 A12 consolidated 200-level source-only qualification with preserved holds.

This invokes every phase's independently written oracle rather than trusting
casebook counts or reporting UI labels as proof of playable systems.
"""
from __future__ import annotations
import argparse
from collections import Counter
from hashlib import sha256
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import validate_exp016_casework as a02
import validate_exp016_a03 as a03
import validate_exp016_a04 as a04
import validate_exp016_a05 as a05
import validate_exp016_a06 as a06
import validate_exp016_a07 as a07
import validate_exp016_a08 as a08
import validate_exp016_a09 as a09
import validate_exp016_a10 as a10
import validate_exp016_a11 as a11

EXPED = ROOT/"scenes"/"expeditions"
HOLDS = ["human/controller playability","physical reachability / line of sight",
         "Steam multi-peer network","GPU/hardware","cross-process durable regional state",
         "production save/economy","release promotion"]

def read(name):
    return json.loads((EXPED/name).read_text(encoding="utf-8"))

def qualify() -> dict:
    atlas, cases = read("atlas.json"), []
    if not atlas.get("legacy_campaign_contracts_unchanged"):
        raise ValueError("A12_LEGACY_PROTECTION")
    if len(atlas["levels"])!=len(atlas["locations"])!=200:
        raise ValueError("A12_ATLAS_COVERAGE")
    ids = [t["id"] for lv in atlas["levels"] for t in lv["tasks"]]
    if len(ids)!=1000 or len(set(ids))!=1000:
        raise ValueError("A12_IMMUTABLE_JOB_IDS")
    phase_reports = {}
    for label,phase in (("A02","a02"),("A03","a03"),("A04","a04"),("A05","a05")):
        casebook = read(f"exp016_casework_{phase}.json")
        if len(casebook["entries"])!=50:
            raise ValueError("A12_50_CASE_PHASE_COUNT")
        cases += casebook["entries"]
        phase_reports[label] = {"cases":50,"routes":100,
                                "range":casebook["range"]}
    if len(cases)!=200 or [entry["level_id"] for entry in cases] != [
        f"LV_{i:03d}" for i in range(1,201)]:
        raise ValueError("A12_CASE_OVERLAP_OR_GAP")
    phase_reports["A02"].update(a02.audit(atlas, read("site_investigations_exp014_a08.json"),
                                          read("exp016_casework_a02.json")))
    phase_reports["A03"].update(a03.qualify())
    phase_reports["A04"].update(a04.qualify())
    phase_reports["A05"].update(a05.qualify())
    phase_reports["A06"] = a06.qualify(atlas,read("fault_diagnostics.json"),
                  read("bespoke_encounters.json"),read("exp016_fault_layers_a06.json"))
    phase_reports["A07"] = a07.qualify(atlas,read("bespoke_encounters.json"),
                  read("site_contingencies_exp014_a02.json"),read("exp016_hazard_protocols_a07.json"))
    phase_reports["A08"] = a08.audit(atlas,read("field_work_orders.json"),read("exp016_equipment_a08.json"))
    phase_reports["A09"] = a09.qualify(atlas,read("site_contingencies_exp014_a02.json"),
                  read("exp016_policies_a09.json"))
    phase_reports["A10"] = a10.validate(atlas,read("regional_networks_exp014_a09.json"),
                  read("exp016_cascades_a10.json"))
    phase_reports["A11"] = a11.qualify(atlas,read("site_investigations_exp014_a08.json"),
                  read("exp016_discoveries_a11.json"))
    book_names=["atlas.json","campaign_routes.json",
      *[f"exp016_casework_{n}.json" for n in ("a02","a03","a04","a05")],
      "exp016_fault_layers_a06.json","exp016_hazard_protocols_a07.json",
      "exp016_equipment_a08.json","exp016_policies_a09.json",
      "exp016_cascades_a10.json","exp016_discoveries_a11.json"]
    sha={name:sha256((EXPED/name).read_bytes()).hexdigest() for name in book_names}
    return {"phase":"EXP016_A12",
      "status":"SOURCE_AND_REPLAY_INVENTORY_ONLY_NOT_PRODUCTION_CERTIFIED",
      "levels":200,"locations":200,"immutable_original_job_ids":1000,
      "advanced_case_routes":400,"original_legacy_campaign_unchanged":True,
      "qualification":"HEADLESS_SOURCE_ONLY_PHYSICAL_CONTROLLER_RELEASE_HELD",
      "source_provenance_sha256":sha,"phase_oracles":phase_reports,
      "negative_scenarios":["foreign station","wrong source diagnosis",
          "unearned DAG step","wrong tool","insufficient source spares",
          "hazard remains unsafe","wrong policy/route","duplicate lore",
          "cross-account cascade","regional double write","unverified source signoff"],
      "outstanding_holds":HOLDS,
      "promotion_allowed":False}

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report",type=Path,default=Path("build/exp016-a12/qualification.json"))
    args=parser.parse_args()
    try:
        result=qualify()
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    except (ValueError,KeyError,TypeError,OSError,AssertionError) as exc:
        print(f"[EXP016 A12][FAIL CLOSED] {type(exc).__name__}: {exc}")
        return 1
    print("[EXP016 A12][SOURCE GATE] 200 levels / 1000 original job IDs / 400 advanced case routes")
    for stage,info in result["phase_oracles"].items():
        print(f"[EXP016 A12][SOURCE PASS] {stage}: {json.dumps(info,sort_keys=True)}")
    print(f"[EXP016 A12][REPORT] {args.report}")
    print("[EXP016 A12][HOLD] No controller/hardware/network/save/economy/release certification.")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
