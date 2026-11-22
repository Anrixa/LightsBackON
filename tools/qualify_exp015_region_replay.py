#!/usr/bin/env python3
"""EXP015 A06: independent three-junction original regional host replay oracle.

Ground source eligibility in original A09/EXP05 route receipts, and require
A01/A02/A03/A04/A05 all bind distinct authentic sites and original topology.
No real player, hardware, online session or production-save claims.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

if __package__:
    from .validate_exp015_emergencies import audit as audit_a01
    from .validate_exp015_cascades import audit as audit_a02
    from .validate_exp015_assurance import audit as audit_a05, original_supply
    from .validate_exp015_finales import feeder_tree
else:
    from validate_exp015_emergencies import audit as audit_a01
    from validate_exp015_cascades import audit as audit_a02
    from validate_exp015_assurance import audit as audit_a05, original_supply
    from validate_exp015_finales import feeder_tree

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "scenes" / "expeditions"
PATHS = (
    "regional_networks_exp014_a09.json",
    "region_incidents_exp015_a01.json",
    "region_cascades_exp015_a02.json",
    "region_finales_exp015_a03.json",
    "region_aftercare_exp015_a04.json",
    "region_assurance_exp015_a05.json",
)
HOLD = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"


def demand(check: bool, code: str) -> None:
    if not check:
        raise ValueError("EXP015_A06_" + code)


def load() -> tuple[dict, dict, dict, dict, dict, dict]:
    return tuple(json.loads((BASE / path).read_text(encoding="utf-8"))
                 for path in PATHS)


def audit(a09: dict, a01: dict, a02: dict,
          a03: dict, a04: dict, a05: dict) -> dict:
    # These independent parent oracles must still pass their own checks.
    audit_a01(a09, a01)
    audit_a02(a09, a02)
    audit_a05(a09, a03, a04, a05)
    stages = set()
    mechanics = set()
    branches = {
        "critical_first": {"critical_live": 0, "recharge_ready": 0},
        "resilience_first": {"critical_live": 0, "recharge_ready": 0},
    }
    details = []
    for index, region in enumerate(a09["regions"]):
        sites, parents = feeder_tree(region)
        entry_first = a01["entries"][index]
        entry_second = a02["entries"][index]
        entry_final = a03["entries"][index]
        entry_after = a04["entries"][index]
        entry_assurance = a05["entries"][index]
        first, second, final = sites[3], sites[6], sites[7]
        demand(entry_first.get("incident_site_id") == first and
               entry_second.get("junction_site_id") == second and
               entry_final.get("finale_site_id") == final and
               entry_after.get("finale_site_id") == final and
               entry_assurance.get("finale_site_id") == final and
               first != second != final and
               all(node not in stages for node in (first, second, final)),
               "CROSS_PHASE_ORIGINAL_DISPATCH_BINDING")
        stages.update((first, second, final))
        feeder_critical = next(f for f in region["primary_feeders"]
                               if f["to"] == region["critical_service_site"])
        feeder_shelter = next(f for f in region["primary_feeders"]
                              if f["to"] == region["shelter_service_site"])
        demand(entry_assurance["critical_feeder_id"] ==
               feeder_critical["edge_id"]
               and entry_after["recovery_feeder_id"] ==
               feeder_shelter["edge_id"]
               and entry_first["standby_tie_id"] ==
               region["standby_ties"][0]["edge_id"]
               and entry_second["backfeed_tie_id"] ==
               region["standby_ties"][1]["edge_id"],
               "CROSS_PHASE_ORIGINAL_NETWORK_BONDS")
        signature = (
            parents,
            sites.index(region["critical_service_site"]),
            sites.index(region["reserve_anchor_site"]),
            sites.index(region["standby_ties"][0]["from"]),
            sites.index(region["standby_ties"][1]["from"]),
            region["risk_class"],
            region["initial_reserve_pu"],
        )
        digest = hashlib.sha256(repr(signature).encode("utf-8")).hexdigest()
        demand(digest not in mechanics, "NON_UNIQUE_ID_NORMALIZED_NETWORK")
        mechanics.add(digest)
        modes = {}
        for mode, counts in branches.items():
            source = original_supply(region, mode)
            demand(not source["finale_restored"]
                   and source["reserve_before_recharge"] >= 0,
                   "EARLY_RESTORATION_OR_RESERVE_UNDERFLOW")
            counts["critical_live"] += int(source["critical_live"])
            counts["recharge_ready"] += int(source["recharge_eligible"])
            modes[mode] = {
                "critical_live": source["critical_live"],
                "reserve_before_a05": source["reserve_before_recharge"],
                "recharge_ready": source["recharge_eligible"],
            }
        details.append({
            "region_id": region["region_id"], "original_dispatches": [
                first, second, final],
            "mechanics_sha256": digest, "source_routes": modes,
        })
        print(f"EXP015_A06_SPINE {index+1:02}/25 {region['region_id']} "
              f"{first}->{second}->{final} sha={digest[:12]}")
    demand(len(stages) == 75 and len(mechanics) == 25, "FULL_REGION_COVERAGE")
    demand(branches["critical_first"] ==
           {"critical_live": 25, "recharge_ready": 3}
           and branches["resilience_first"] ==
           {"critical_live": 0, "recharge_ready": 0},
           "RECEIPT_BRANCH_DRIFT")
    return {
        "ok": True, "phase": "EXP015_A06",
        "original_regions": 25, "original_unique_stages": len(stages),
        "original_source_mechanical_signatures": len(mechanics),
        "authenticated_3_dispatch_scenarios_required": 50,
        "original_branch_effects": branches,
        "source_qualification": HOLD,
        "original_saves_rewards_levels_tasks_unchanged": True,
        "physical_controller_steam_release_certified": False,
        "cases": details,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    outcome = audit(*load())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(outcome, sort_keys=True, indent=2) + "\n",
                               encoding="utf-8")
    print("EXP015_A06_SOURCE_PASS " + json.dumps({
        k: v for k, v in outcome.items() if k != "cases"
    }, sort_keys=True))


if __name__ == "__main__":
    main()
