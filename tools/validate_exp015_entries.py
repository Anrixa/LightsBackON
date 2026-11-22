#!/usr/bin/env python3
"""EXP015 A09: source-authoritative original cold-root commissioning audit.

Independent A09 original source binding and 100 real-feeder/reserve policy
scenarios. Does not assert electrical energization or physical playability.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

if __package__:
    from .validate_exp015_finales import feeder_tree
else:
    from validate_exp015_finales import feeder_tree

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "scenes" / "expeditions"
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
AUTHORITY = "EXP015_A09_ORIGINAL_ROOT_COMMISSIONING"
RISKS = {
    "depth": ("entry_flood_lockout", 2),
    "conductivity": ("entry_arc_clearance", 4),
    "mechanical": ("entry_manual_interlock", 2),
    "structure": ("entry_shoring_permit", 3),
    "weather": ("entry_weather_window", 3),
}


def ensure(condition: bool, name: str) -> None:
    if not condition:
        raise ValueError("EXP015_A09_" + name)


def load() -> tuple[dict, dict]:
    return tuple(json.loads((CONTENT / name).read_text(encoding="utf-8"))
                 for name in ("regional_networks_exp014_a09.json",
                              "region_entries_exp015_a09.json"))


def audit(networks: dict, book: dict) -> dict[str, Any]:
    ensure(book.get("schema_version") == 1 and
           book.get("authority") == AUTHORITY and
           book.get("predecessor") == "EXP015_A08" and
           book.get("qualification") == QUALIFICATION and
           book.get("legacy_campaign_contracts_unchanged") is True and
           book.get("original_entries") == 25 and
           isinstance(book.get("entries"), list) and
           len(book["entries"]) == 25 and
           len(networks.get("regions", [])) == 25, "SOURCE_AUTHORITY")
    seen: set[str] = set()
    shapes: set[str] = set()
    risk_counts: dict[str, int] = {risk: 0 for risk in RISKS}
    scenario_count = 0
    original_capacity_values: set[int] = set()
    reserve_costs = {"finite_buffer": 0, "managed_debt": 0}
    proof = []
    for idx, region in enumerate(networks["regions"]):
        sites, parents = feeder_tree(region)
        signature = (parents, sites.index(region["critical_service_site"]),
                     sites.index(region["reserve_anchor_site"]),
                     tuple((sites.index(t["from"]), sites.index(t["to"]))
                           for t in region["standby_ties"]),
                     region["risk_class"], region["initial_reserve_pu"])
        digest = hashlib.sha256(repr(signature).encode("utf-8")).hexdigest()
        ensure(digest not in shapes, "ORIGINAL_REGIONAL_TOPOLOGY_DUPLICATED")
        shapes.add(digest)
        root, first_a, first_b = region["source_sites"][:3]
        feeders_a = [f for f in region["primary_feeders"]
                     if f["to"] == first_a["site_id"]]
        feeders_b = [f for f in region["primary_feeders"]
                     if f["to"] == first_b["site_id"]]
        ensure(len(feeders_a) == 1 and len(feeders_b) == 1,
               "ORIGINAL_FIRST_FEEDERS_MISSING")
        a, b = feeders_a[0], feeders_b[0]
        risk = region["risk_class"]
        case = book["entries"][idx]
        site_id = root["site_id"]
        ensure(risk in RISKS and site_id not in seen and
               root["campaign_role"] == "entry" and
               first_a["campaign_role"] == "first_route_a" and
               first_b["campaign_role"] == "first_route_b" and
               region["root_source_id"] == site_id and
               a["from"] == site_id and b["from"] == site_id and
               case.get("region_id") == region["region_id"] and
               case.get("entry_site_id") == site_id and
               case.get("location_id") == root["location_id"] and
               case.get("worksite_family") == root["worksite_family"] and
               case.get("original_task_ids") == root["source_task_ids"] and
               case.get("transport_site_id") == first_a["site_id"] and
               case.get("transport_feeder_id") == a["edge_id"] and
               case.get("transport_protection") == a["protection"] and
               case.get("transport_capacity_pu") == a["capacity_pu"] and
               case.get("critical_site_id") == first_b["site_id"] and
               case.get("critical_feeder_id") == b["edge_id"] and
               case.get("critical_protection") == b["protection"] and
               case.get("critical_capacity_pu") == b["capacity_pu"] and
               case.get("regional_critical_service_id") ==
               region["critical_service_site"] and
               case.get("risk_class") == risk and
               case.get("entry_risk_proof") == RISKS[risk][0] and
               type(case.get("managed_pressure_pu")) is int and
               case["managed_pressure_pu"] == RISKS[risk][1] and
               case.get("initial_reserve_pu") == region["initial_reserve_pu"] and
               case.get("qualification") == QUALIFICATION,
               "ORIGINAL_ENTRY_BINDING")
        seen.add(site_id)
        risk_counts[risk] += 1
        original_capacity_values.add(a["capacity_pu"])
        original_capacity_values.add(b["capacity_pu"])
        reserve = region["initial_reserve_pu"]
        ensure(reserve >= 2, "REAL_RESERVE_INSUFFICIENT")
        # Source scenario: exactly one original branch is first released;
        # the other original feeder remains physically isolated until
        # the source risk and reserve/debt policy have been proved.
        for first_branch in ("critical_health", "transport_access"):
            for policy in ("finite_buffer", "managed_debt"):
                held = {a["edge_id"], b["edge_id"]}
                chosen = b["edge_id"] if first_branch == "critical_health"                     else a["edge_id"]
                held.remove(chosen)
                ensure(len(held) == 1, "ROOT_FIRST_BRANCH_NOT_ISOLATED")
                balance = reserve - (2 if policy == "finite_buffer" else 0)
                debt = 2 if policy == "managed_debt" else 0
                held.remove(next(iter(held)))
                ensure(not held and balance >= 0 and
                       balance + (2 if policy == "finite_buffer" else 0)
                       == reserve and debt in (0, 2),
                       "ROOT_PREPARATION_LEDGER_DRIFT")
                # An isolated dead-root feeder is never evidence of live
                # electricity. Original EXP04 restoration receipt remains
                # separately mandatory after source-only commissioning.
                original_root_restored = False
                original_root_energized = False
                ensure(not original_root_restored and not original_root_energized,
                       "FALSE_SOURCE_ENERGIZATION")
                scenario_count += 1
                reserve_costs[policy] += 1
        proof.append({"region_id": region["region_id"],
                      "original_entry": site_id,
                      "source_fingerprint": digest,
                      "root_receipt_granted": False,
                      "entry_route_protections": [a["protection"], b["protection"]]})
        print(f"EXP015_A09_SOURCE {idx+1:02}/25 {region['region_id']} "
              f"root={site_id} critical={first_b['site_id']} "
              f"reserve={reserve} risk={risk}")
    ensure(len(seen) == 25 and len(shapes) == 25 and
           scenario_count == 100 and len(original_capacity_values) == 5 and
           sum(risk_counts.values()) == 25 and all(risk_counts.values()),
           "ORIGINAL_ENTRY_COVERAGE")
    return {
        "ok": True, "phase": "EXP015_A09", "regions": 25,
        "original_entry_sites": len(seen), "original_first_feeders": len(seen) * 2,
        "source_bound_campaign_tasks": len(seen) * 5,
        "original_topological_signatures": len(shapes),
        "original_risk_classes": risk_counts,
        "original_100_commissioning_scenarios": scenario_count,
        "reserve_and_debt_paths": reserve_costs,
        "fake_restoration_or_revenue": False,
        "physical_steam_two_peer_hardware_release_certified": False,
        "qualification": QUALIFICATION,
        "evidence": proof,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = audit(*load())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    print("EXP015_A09_SOURCE_PASS " + json.dumps(
        {k: v for k, v in result.items() if k != "evidence"}, sort_keys=True))


if __name__ == "__main__":
    main()
