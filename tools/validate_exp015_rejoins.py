#!/usr/bin/env python3
"""EXP015 A08 — 50 real A09 rejoin feeder and prior-route proof audits."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

if __package__:
    from .validate_exp015_finales import feeder_tree
    from .validate_exp015_alt_routes import audit as audit_alternates
else:
    from validate_exp015_finales import feeder_tree
    from validate_exp015_alt_routes import audit as audit_alternates

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "scenes" / "expeditions"
HOLD = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
RISK = {
    "depth": ("rejoin_dewater_and_lockout", 3),
    "conductivity": ("rejoin_arc_free_continuity", 5),
    "mechanical": ("rejoin_mechanical_interlock", 2),
    "structure": ("rejoin_shoring_clearance", 4),
    "weather": ("rejoin_weather_seal_proof", 3),
}


def demand(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError("EXP015_A08_" + code)


def load() -> tuple[dict, dict, dict]:
    return tuple(json.loads((BASE / path).read_text(encoding="utf-8"))
                 for path in (
                    "regional_networks_exp014_a09.json",
                    "region_alt_routes_exp015_a07.json",
                    "region_rejoins_exp015_a08.json",
                 ))


def network_live(region: dict, restored: set[str],
                 isolated: set[str] | None = None) -> set[str]:
    """Only original restored sites with actual intact upstream feeders live."""
    blocked = isolated or set()
    root = region["root_source_id"]
    alive = {root} if root in restored else set()
    for _ in range(8):
        for feeder in region["primary_feeders"]:
            if feeder["edge_id"] not in blocked and feeder["from"] in alive and (
                    feeder["to"] in restored):
                alive.add(feeder["to"])
    return alive


def event_proof(feeder: str, site_restored: bool,
                healthy_feeder: bool, events: list[dict]) -> bool:
    """A09 trusted event log: trip->clear_fault->reset, no later isolate."""
    if not site_restored or not healthy_feeder:
        return False
    step = 0
    for event in events:
        if event.get("asset") != feeder:
            continue
        action = event.get("action")
        if action == "trip_feeder":
            step = 1
        elif action == "clear_fault" and step == 1:
            step = 2
        elif action == "reset_feeder" and step == 2:
            step = 3
        elif action == "isolate_feeder":
            step = 0
    return step == 3


def audit(networks: dict, alternates: dict,
          rejoins: dict) -> dict[str, Any]:
    audit_alternates(networks, alternates)
    demand(rejoins.get("schema_version") == 1 and
           rejoins.get("authority") == "EXP015_A08_REAL_ROUTE_EVIDENCE_REJOIN"
           and rejoins.get("predecessor") == "EXP015_A07" and
           rejoins.get("qualification") == HOLD and
           rejoins.get("legacy_campaign_contracts_unchanged") is True and
           rejoins.get("original_rejoins") == 50 and
           isinstance(rejoins.get("entries"), list) and
           len(rejoins["entries"]) == 50, "REJOIN_AUTHORITY")
    seen: set[str] = set()
    shapes: set[str] = set()
    roles = {"first_rejoin": 0, "second_rejoin": 0}
    viable = {
        "first_a_second_a": 0, "first_a_second_b": 0,
        "first_b_second_a": 0, "first_b_second_b": 0,
    }
    outcomes = []
    for i, region in enumerate(networks["regions"]):
        sites, parents = feeder_tree(region)
        signature = (parents, sites.index(region["critical_service_site"]),
                     sites.index(region["reserve_anchor_site"]),
                     tuple((sites.index(e["from"]), sites.index(e["to"]))
                           for e in region["standby_ties"]),
                     region["risk_class"], region["initial_reserve_pu"])
        digest = hashlib.sha256(repr(signature).encode("utf-8")).hexdigest()
        demand(digest not in shapes, "ORIGINAL_TOPOLOGY_COLLISION")
        shapes.add(digest)
        for j, slot in enumerate((3, 6)):
            site = region["source_sites"][slot]
            case = rejoins["entries"][2 * i + j]
            feeder = next(f for f in region["primary_feeders"]
                          if f["to"] == site["site_id"])
            a = region["source_sites"][1 if slot == 3 else 4]
            b = region["source_sites"][2 if slot == 3 else 5]
            feeder_a = next(f for f in region["primary_feeders"]
                            if f["to"] == a["site_id"])
            feeder_b = next(f for f in region["primary_feeders"]
                            if f["to"] == b["site_id"])
            finale = region["source_sites"][7]
            final_feeder = next(f for f in region["primary_feeders"]
                                if f["to"] == finale["site_id"])
            final_tie = next(t for t in region["standby_ties"]
                             if t["to"] == finale["site_id"])
            role = "first_rejoin" if slot == 3 else "second_rejoin"
            second = slot == 6
            risk = region["risk_class"]
            demand(risk in RISK and site["site_id"] not in seen and
                   case.get("region_id") == region["region_id"] and
                   case.get("join_site_id") == site["site_id"] and
                   case.get("location_id") == site["location_id"] and
                   case.get("join_role") == role and
                   case.get("source_task_ids") == site["source_task_ids"] and
                   case.get("join_feeder_id") == feeder["edge_id"] and
                   case.get("join_upstream_site_id") == feeder["from"] and
                   case.get("route_a_site_id") == a["site_id"] and
                   case.get("route_a_feeder_id") == feeder_a["edge_id"] and
                   case.get("route_b_site_id") == b["site_id"] and
                   case.get("route_b_feeder_id") == feeder_b["edge_id"] and
                   case.get("critical_service_site") ==
                   region["critical_service_site"] and
                   case.get("finale_site_id") == finale["site_id"] and
                   case.get("finale_normal_feeder_id") ==
                   (final_feeder["edge_id"] if second else "") and
                   case.get("finale_standby_tie_id") ==
                   (final_tie["edge_id"] if second else "") and
                   case.get("finale_standby_source_id") ==
                   (final_tie["from"] if second else "") and
                   case.get("original_fault_signature") ==
                   region["fault_signature"] and
                   case.get("original_recovery_procedure") ==
                   region["recovery_procedure"] and
                   case.get("risk_class") == risk and
                   case.get("rejoin_risk_protocol") == RISK[risk][0] and
                   type(case.get("managed_pressure_pu")) is int and
                   case["managed_pressure_pu"] == RISK[risk][1] and
                   case.get("qualification") == HOLD,
                   "REJOIN_ORIGINAL_FEEDER_BINDING")
            seen.add(site["site_id"])
            roles[role] += 1
            if second:
                for first in ("a", "b"):
                    for branch in ("a", "b"):
                        restored = {sites[0], sites[1 if first == "a" else 2],
                                    sites[3], sites[4 if branch == "a" else 5]}
                        live = network_live(region, restored, {feeder["edge_id"]})
                        demand(sites[6] not in restored and sites[7] not in restored,
                               "FORGED_REJOIN_OR_FINALE_RESTORATION")
                        viable[f"first_{first}_second_{branch}"] += int(
                            final_tie["from"] in live and
                            region["initial_reserve_pu"] >= 2)
        outcomes.append({"region_id": region["region_id"],
                         "original_join_ids": [sites[3], sites[6]],
                         "network_sha256": digest})
        print(f"EXP015_A08_SOURCE {i+1:02}/25 {region['region_id']} "
              f"joins={sites[3]},{sites[6]}")
    demand(len(shapes) == 25 and len(seen) == 50 and
           roles == {"first_rejoin": 25, "second_rejoin": 25},
           "REJOIN_ORIGINAL_COVERAGE")
    demand(viable == {"first_a_second_a": 13, "first_a_second_b": 11,
                      "first_b_second_a": 9, "first_b_second_b": 11},
           "STANDBY_REAL_SOURCE_FEASIBILITY_DRIFT")
    good = [{"asset": "A", "action": "trip_feeder"},
            {"asset": "A", "action": "clear_fault"},
            {"asset": "A", "action": "reset_feeder"}]
    demand(event_proof("A", True, True, good) and
           not event_proof("A", False, True, good) and
           not event_proof("A", True, False, good) and
           not event_proof("A", True, True, list(reversed(good))) and
           not event_proof("A", True, True, good +
                           [{"asset": "A", "action": "isolate_feeder"}]),
           "A09_EVENT_ORDER_PROOF_WEAKENED")
    return {
        "ok": True, "phase": "EXP015_A08",
        "original_rejoin_sites": len(seen), "regions": 25,
        "original_network_signatures": len(shapes),
        "original_role_counts": roles,
        "source_mechanical_route_scenarios": 150,
        "source_feasible_standby_rejoins": viable,
        "qualified_original_A09_event_proof": True,
        "qualification": HOLD,
        "new_levels_tasks_rewards_production_saves": False,
        "playability_hardware_steam_release_certified": False,
        "evidence": outcomes,
    }


def main() -> None:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--report", type=Path)
    args = cli.parse_args()
    result = audit(*load())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    print("EXP015_A08_SOURCE_PASS " + json.dumps(
        {k: v for k, v in result.items() if k != "evidence"}, sort_keys=True))


if __name__ == "__main__":
    main()
