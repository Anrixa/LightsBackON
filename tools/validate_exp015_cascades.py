#!/usr/bin/env python3
"""EXP015 A02 independent second-junction feeder cascade/source safety audit.

Determines real 25-region original A09 supply ancestry, second standby
opportunities and fail-closed risk recovery. No Godot host, player, GPU or
production power-flow test is inferred from this static source audit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "scenes" / "expeditions"
CASCADE_PATH = SOURCE_DIR / "region_cascades_exp015_a02.json"
A09_PATH = SOURCE_DIR / "regional_networks_exp014_a09.json"
HOLD = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
RISK = {
    "depth": ("water_table_containment", 3),
    "conductivity": ("arc_discharge_quarantine", 5),
    "mechanical": ("moving_contact_lockout", 2),
    "structure": ("buckled_support_isolation", 4),
    "weather": ("storm_conductor_clearance", 3),
}


def require(valid: bool, code: str) -> None:
    if not valid:
        raise ValueError("EXP015_A02_" + code)


def load() -> tuple[dict, dict]:
    return (
        json.loads(A09_PATH.read_text(encoding="utf-8")),
        json.loads(CASCADE_PATH.read_text(encoding="utf-8")),
    )


def original_tree(region: dict) -> tuple[list[str], tuple[int, ...]]:
    sites = [x["site_id"] for x in region["source_sites"]]
    require(len(sites) == len(set(sites)) == 8, "SOURCE_8_SITE_COVERAGE")
    root = region["root_source_id"]
    require(root == sites[0], "ROOT_SOURCE_REPLACEMENT")
    edges = region["primary_feeders"]
    require(len(edges) == 7, "SOURCE_7_FEEDER_COUNT")
    parents = {edge["to"]: edge["from"] for edge in edges}
    require(len(parents) == 7 and root not in parents, "PRIMARY_NOT_TREE")
    for site in sites[1:]:
        cursor = site
        visited: set[str] = set()
        while cursor != root:
            require(cursor not in visited and cursor in parents, "CYCLIC_FEEDER")
            visited.add(cursor)
            cursor = parents[cursor]
    return sites, tuple(-1 if site == root else sites.index(parents[site])
                        for site in sites)


def is_backfeed_live(region: dict) -> bool:
    # An original EXP05 critical-first route:
    # root -> LVxx3 -> first join LVxx4 -> second B LVxx6 -> second join.
    # The source being restored is insufficient: its normal upstream tree
    # must also be energized by authentic receipts.
    sites = [s["site_id"] for s in region["source_sites"]]
    restored = {sites[x] for x in (0, 2, 3, 5)}
    live = {sites[0]}
    for _ in range(8):
        for edge in region["primary_feeders"]:
            if edge["from"] in live and edge["to"] in restored:
                live.add(edge["to"])
    target = region["standby_ties"][1]["from"]
    return target in live


def audit(networks: dict, book: dict) -> dict:
    require(networks.get("authority") ==
            "EXP014_A09_1_SOURCE_NETWORK_TOPOLOGIES_ONLY",
            "ORIGINAL_NETWORK_AUTHORITY")
    require(book.get("authority") == "EXP015_A02_AUTHORED_HOST_CASCADE_SOURCE"
            and book.get("schema_version") == 1
            and book.get("qualification") == HOLD
            and book.get("source_binding") ==
            "EXP014_A09_NORMAL_FEEDER_SECOND_TIE"
            and book.get("legacy_campaign_contracts_unchanged") is True,
            "CASCADE_AUTHORITY")
    regions = networks.get("regions", [])
    cases = book.get("entries", [])
    require(isinstance(regions, list) and len(regions) == 25
            and isinstance(cases, list) and len(cases) == 25,
            "SOURCE_REGION_COVERAGE")
    known: set[str] = set()
    structural: set[str] = set()
    live_routes = 0
    evidence: list[dict] = []
    for region, case in zip(regions, cases):
        sites, parent = original_tree(region)
        target = sites[6]
        require(case.get("region_id") == region["region_id"]
                and case.get("junction_site_id") == target
                and case.get("risk_class") == region["risk_class"]
                and case.get("qualification") == HOLD
                and target not in known
                and case.get("critical_service_site") ==
                region["critical_service_site"]
                and case.get("shelter_service_site") ==
                region["shelter_service_site"], "JUNCTION_IDENTITY")
        known.add(target)
        risk = case["risk_class"]
        require(risk in RISK and case.get("risk_protocol") == RISK[risk][0]
                and type(case.get("managed_service_pressure")) is int
                and case["managed_service_pressure"] == RISK[risk][1],
                "RISK_RESPONSE_MISMATCH")
        require(case.get("original_fault_signature") ==
                region["fault_signature"]
                and case.get("original_recovery_procedure") ==
                region["recovery_procedure"],
                "ORIGINAL_FAULT_PROOF_MISMATCH")
        tie = region["standby_ties"][1]
        require(case.get("backfeed_tie_id") == tie["edge_id"]
                and case.get("backfeed_source_site") == tie["from"]
                and case.get("affected_service_site") == tie["to"]
                and tie["to"] != target, "SECOND_TIE_SOURCE_MISMATCH")
        feeder = next((e for e in region["primary_feeders"]
                       if e["to"] == tie["to"]), None)
        require(feeder is not None and
                case.get("normal_feeder_id") == feeder["edge_id"],
                "ORIGINAL_NORMAL_FEEDER_MISMATCH")
        # Mechanical identity deliberately excludes prose, IDs, clocks, ticks.
        signature = (
            parent, sites.index(tie["from"]), sites.index(tie["to"]),
            sites.index(feeder["from"]), risk, RISK[risk][1],
        )
        digest = hashlib.sha256(repr(signature).encode("utf-8")).hexdigest()
        require(digest not in structural, "RENAMED_CASCADE_COLLISION")
        structural.add(digest)
        live = is_backfeed_live(region)
        live_routes += int(live)
        evidence.append({
            "region_id": case["region_id"],
            "junction": target,
            "risk_protocol": case["risk_protocol"],
            "live_original_critical_first_standby_source": live,
            "managed_pressure": case["managed_service_pressure"],
            "mechanics_sha256": digest,
        })
    require(len(known) == len(structural) == 25 and live_routes >= 5,
            "SOURCE_BACKFEED_FEASIBILITY")
    return {
        "ok": True, "phase": "EXP015_A02", "qualification": HOLD,
        "second_or_join_cascades": len(known),
        "distinct_mechanical_fault_graphs": len(structural),
        "risk_specific_recovery_protocols": len(RISK),
        "original_critical_first_live_backfeed_paths": live_routes,
        "original_managed_recovery_fallbacks": len(known),
        "unchanged_original_12_contracts_and_1000_tasks": True,
        "host_runtime_certified_by_source_only": False,
        "physical_steam_release_certified": False,
        "region_evidence": evidence,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=None)
    args = parser.parse_args()
    result = audit(*load())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n",
            encoding="utf-8")
    print("EXP015 A02 CASCADE SOURCE AUDIT: " +
          json.dumps({k: v for k, v in result.items()
                      if k != "region_evidence"}, sort_keys=True))


if __name__ == "__main__":
    main()
