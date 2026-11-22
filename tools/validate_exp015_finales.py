#!/usr/bin/env python3
"""EXP015 A03: verify 25 real regional finale portfolios and 50 source routes.

Source checks do not count renamed levels, timers or cosmetic action labels as
new mechanics. Physical player, hardware, real electricity and release remain HOLD.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "scenes/expeditions/regional_networks_exp014_a09.json"
FINALES = ROOT / "scenes/expeditions/region_finales_exp015_a03.json"
HOLD = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
RISKS: dict[str, tuple[str, int]] = {
    "depth": ("groundwater_isolation_review", 3),
    "conductivity": ("arc_clearance_assurance", 5),
    "mechanical": ("load_transfer_interlock_review", 2),
    "structure": ("support_stability_release", 4),
    "weather": ("exposed_conductor_reclearance", 3),
}


def demand(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError("EXP015_A03_" + code)


def load() -> tuple[dict, dict]:
    return (json.loads(SOURCE.read_text(encoding="utf-8")),
            json.loads(FINALES.read_text(encoding="utf-8")))


def feeder_tree(region: dict) -> tuple[list[str], tuple[int, ...]]:
    sites = [site["site_id"] for site in region["source_sites"]]
    demand(len(sites) == len(set(sites)) == 8, "SOURCE_EIGHT_SITES")
    demand(region["root_source_id"] == sites[0], "SOURCE_ROOT")
    feeders = region["primary_feeders"]
    demand(len(feeders) == 7, "SOURCE_SEVEN_FEEDERS")
    parent = {edge["to"]: edge["from"] for edge in feeders}
    demand(len(parent) == 7 and sites[0] not in parent, "SOURCE_TREE_SIZE")
    for site in sites[1:]:
        seen: set[str] = set()
        pointer = site
        while pointer != sites[0]:
            demand(pointer in parent and pointer not in seen, "SOURCE_CYCLIC_FEEDER")
            seen.add(pointer)
            pointer = parent[pointer]
    return sites, tuple(-1 if site == sites[0] else sites.index(parent[site])
                        for site in sites)


def source_supplies(region: dict, mode: str) -> dict[str, bool]:
    """Original EXP05 branch receipts, not invented completed player missions."""
    sites = [site["site_id"] for site in region["source_sites"]]
    slots = (0, 2, 3, 5, 6) if mode == "critical_first" else (0, 1, 3, 4, 6)
    restored = {sites[i] for i in slots}
    live = {sites[0]}
    for _ in range(8):
        for edge in region["primary_feeders"]:
            if edge["from"] in live and edge["to"] in restored:
                live.add(edge["to"])
    shelter_incoming = next(
        edge for edge in region["primary_feeders"]
        if edge["to"] == region["shelter_service_site"])
    return {
        "critical_energized": region["critical_service_site"] in live,
        "shelter_supply_ready": shelter_incoming["from"] in live,
    }


def audit(regions_book: dict, finale_book: dict) -> dict[str, Any]:
    demand(regions_book.get("authority") ==
           "EXP014_A09_1_SOURCE_NETWORK_TOPOLOGIES_ONLY",
           "REGIONAL_AUTHORITY")
    demand(finale_book.get("authority") ==
           "EXP015_A03_AUTHORED_FINALE_TRIAGE_SOURCE" and
           finale_book.get("source_binding") ==
           "EXP014_A09_ORIGINAL_CRITICAL_SHELTER_AND_FEEDER" and
           finale_book.get("qualification") == HOLD and
           finale_book.get("schema_version") == 1 and
           finale_book.get("original_campaign_unchanged") is True,
           "FINALE_AUTHORITY")
    regions = regions_book.get("regions", [])
    finales = finale_book.get("entries", [])
    demand(isinstance(regions, list) and len(regions) == 25 and
           isinstance(finales, list) and len(finales) == 25,
           "FINALE_CARDINALITY")
    seen_sites: set[str] = set()
    distinct_mechanics: set[str] = set()
    modes: dict[str, dict] = {
        "critical_first": {"critical_live": 0, "shelter_ready": 0,
                           "shelter_dark": 0, "reserve_buffer_spend_pu": 0},
        "resilience_first": {"critical_live": 0, "shelter_ready": 0,
                             "shelter_dark": 0, "reserve_buffer_spend_pu": 0},
    }
    evidence = []
    for index, (region, finale) in enumerate(zip(regions, finales)):
        sites, parents = feeder_tree(region)
        end = sites[7]
        demand(finale.get("region_id") == region["region_id"] and
               finale.get("finale_site_id") == end and end not in seen_sites and
               finale.get("shelter_service_site") == end and
               finale.get("critical_service_site") == region["critical_service_site"] and
               finale.get("reserve_anchor_site") == region["reserve_anchor_site"] and
               finale.get("root_source_site") == sites[0] and
               finale.get("source_qualification") == HOLD and
               finale.get("risk_class") == region["risk_class"],
               "ORIGINAL_FINALE_PROVENANCE")
        seen_sites.add(end)
        risk = region["risk_class"]
        demand(risk in RISKS and
               finale.get("risk_closeout_protocol") == RISKS[risk][0] and
               type(finale.get("critical_dark_pressure_pu")) is int and
               finale["critical_dark_pressure_pu"] == RISKS[risk][1],
               "REGIONAL_RISK_PRESSURE")
        critical_incoming = next(
            (e for e in region["primary_feeders"] if e["to"] == region["critical_service_site"]),
            None,
        )
        shelter_incoming = next(
            (e for e in region["primary_feeders"] if e["to"] == end), None
        )
        demand(critical_incoming is not None and shelter_incoming is not None and
               finale.get("critical_feeder_id") == critical_incoming["edge_id"] and
               finale.get("shelter_feeder_id") == shelter_incoming["edge_id"] and
               finale.get("shelter_standby_tie_id") ==
               region["standby_ties"][1]["edge_id"],
               "ORIGINAL_SERVICE_FEEDER_BINDING")
        # No site, feeder, action ID, prose or timing appears in this signature.
        normalized_graph = (
            parents, sites.index(region["critical_service_site"]),
            sites.index(region["reserve_anchor_site"]),
            sites.index(shelter_incoming["from"]),
            sites.index(critical_incoming["from"]),
            sites.index(region["standby_ties"][1]["from"]),
            sites.index(region["standby_ties"][1]["to"]),
            risk, RISKS[risk][1],
        )
        mechanical_hash = hashlib.sha256(
            repr(normalized_graph).encode("utf-8")
        ).hexdigest()
        demand(mechanical_hash not in distinct_mechanics,
               "RENAMED_FINALE_MECHANICAL_COLLISION")
        distinct_mechanics.add(mechanical_hash)
        for mode in ("critical_first", "resilience_first"):
            facts = source_supplies(region, mode)
            modes[mode]["critical_live"] += int(facts["critical_energized"])
            modes[mode]["shelter_ready"] += int(facts["shelter_supply_ready"])
            modes[mode]["shelter_dark"] += int(not facts["shelter_supply_ready"])
            modes[mode]["reserve_buffer_spend_pu"] += (
                0 if facts["shelter_supply_ready"] else 2
            )
        evidence.append({
            "region_id": region["region_id"], "finale": end,
            "risk_protocol": finale["risk_closeout_protocol"],
            "normalized_mechanics_sha256": mechanical_hash,
            "critical_first": source_supplies(region, "critical_first"),
            "resilience_first": source_supplies(region, "resilience_first"),
        })
        print(f"EXP015_A03_SOURCE {index+1:02}/25 {region['region_id']} "
              f"risk={risk} unique_graph={mechanical_hash[:10]}")
    demand(len(seen_sites) == len(distinct_mechanics) == 25,
           "FINALE_MECHANICAL_COVERAGE")
    # These are anchored to the actual A09 source graph and original EXP05
    # restoration spine; a silent network graph change must not be 'certified'.
    demand(modes["critical_first"]["critical_live"] == 25 and
           modes["critical_first"]["shelter_ready"] == 7 and
           modes["resilience_first"]["critical_live"] == 0 and
           modes["resilience_first"]["shelter_ready"] == 12,
           "ORIGINAL_BRANCH_SOURCE_PROFILE_DRIFT")
    return {
        "ok": True, "phase": "EXP015_A03",
        "qualification": HOLD, "finales": 25,
        "original_campaign_routes": 50,
        "risk_protocols": 5,
        "distinct_id_normalized_finale_mechanics": 25,
        "regional_strategy_effects": modes,
        "no_new_levels_tasks_or_original_credits": True,
        "human_controller_hardware_steam_release_certified": False,
        "evidence": evidence,
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
    print("EXP015_A03 FINAL_SOURCE_PASS " + json.dumps({
        key: value for key, value in result.items() if key != "evidence"
    }, sort_keys=True))


if __name__ == "__main__":
    main()
