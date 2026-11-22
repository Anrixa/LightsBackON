#!/usr/bin/env python3
"""EXP015 A01 independent source audit of 25 host-authored emergency chains.

All evidence here is source-only; real authenticated operations are tested by
Godot SessionHost integration and never inferred from JSON route proposals.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / "scenes" / "expeditions"
SOURCE = DIR / "regional_networks_exp014_a09.json"
BOOK = DIR / "region_incidents_exp015_a01.json"
PROTOCOLS = {
    "depth": ("isolate_waterlogged_duct", 2),
    "conductivity": ("prove_arc_free_separation", 3),
    "mechanical": ("secure_mechanical_interlock", 1),
    "structure": ("shore_distressed_feeder", 2),
    "weather": ("weatherproof_exposed_joint", 3),
}
HOLD = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError("EXP015_A01_" + code)


def load() -> tuple[dict, dict]:
    return (json.loads(SOURCE.read_text(encoding="utf-8")),
            json.loads(BOOK.read_text(encoding="utf-8")))


def normalized_tree(region: dict) -> tuple:
    ids = [item["site_id"] for item in region["source_sites"]]
    require(len(ids) == len(set(ids)) == 8, "SOURCE_SITE_CARDINALITY")
    root = region["root_source_id"]
    require(root == ids[0], "ROOT_REASSIGNMENT")
    by_to = {edge["to"]: edge["from"] for edge in region["primary_feeders"]}
    require(len(by_to) == 7 and root not in by_to, "SOURCE_TREE_CARDINALITY")
    for id_ in ids[1:]:
        seen = set()
        cursor = id_
        while cursor != root:
            require(cursor not in seen and cursor in by_to,
                    "SOURCE_FEEDER_GRAPH_NOT_TREE")
            seen.add(cursor)
            cursor = by_to[cursor]
    return tuple(-1 if id_ == root else ids.index(by_to[id_]) for id_ in ids)


def live_root_and_branch(region: dict, proof: str) -> set[str]:
    restored = {region["root_source_id"], proof}
    live = {region["root_source_id"]}
    for _ in range(8):
        for edge in region["primary_feeders"]:
            if edge["from"] in live and edge["to"] in restored:
                live.add(edge["to"])
    return live


def audit(networks: dict, incidents: dict) -> dict:
    require(networks.get("authority") ==
            "EXP014_A09_1_SOURCE_NETWORK_TOPOLOGIES_ONLY",
            "REGIONAL_SOURCE_AUTHORITY")
    require(incidents.get("authority") ==
            "EXP015_A01_AUTHORED_EMERGENCY_RESPONSE_SOURCE" and
            incidents.get("qualification") == HOLD and
            incidents.get("schema_version") == 1 and
            incidents.get("legacy_campaign_contracts_unchanged") is True and
            incidents.get("source_binding") == "EXP014_A09_FEEDER_AND_TIE",
            "INCIDENT_SOURCE_AUTHORITY")
    regions = networks.get("regions", [])
    cases = incidents.get("entries", [])
    require(isinstance(regions, list) and len(regions) == 25 and
            isinstance(cases, list) and len(cases) == 25,
            "REGIONAL_INCIDENT_CARDINALITY")
    keys: set[str] = set()
    signatures: set[str] = set()
    transfer_live = 0
    per_region = []
    for index, (region, incident) in enumerate(zip(regions, cases)):
        site_ids = [site["site_id"] for site in region["source_sites"]]
        location = site_ids[3]
        require(incident.get("region_id") == region["region_id"] and
                incident.get("incident_site_id") == location and
                incident.get("risk_class") == region["risk_class"] and
                incident.get("qualification") == HOLD and
                location not in keys, "SOURCE_SITE_IDENTITY")
        keys.add(location)
        risk = region["risk_class"]
        require(risk in PROTOCOLS and
                incident.get("preparation_protocol") == PROTOCOLS[risk][0] and
                type(incident.get("managed_unserved_pressure_pu")) is int and
                incident["managed_unserved_pressure_pu"] == PROTOCOLS[risk][1],
                "HAZARD_SPECIFIC_RECOVERY_PROTOCOL")
        ties = region["standby_ties"]
        require(len(ties) == 2, "SOURCE_STANDBY_COUNT")
        tie = ties[0]
        require(incident.get("standby_tie_id") == tie["edge_id"] and
                incident.get("standby_source_site") == tie["from"] and
                incident.get("affected_service_site") == tie["to"] and
                incident["affected_service_site"] != location,
                "STANDBY_TOPOLOGY_PIN")
        feeder = next((edge for edge in region["primary_feeders"]
                       if edge["to"] == tie["to"]), None)
        require(feeder is not None and
                incident.get("normal_feeder_id") == feeder["edge_id"],
                "NORMAL_FEEDER_SOURCE_PIN")
        if tie["from"] in live_root_and_branch(region, site_ids[2]) and (
                tie["to"] not in {site_ids[0], site_ids[2]}):
            transfer_live += 1
        # These structural signatures do not contain region, site, feeder,
        # tie IDs, proper names, descriptions, or incident action labels.
        ids = site_ids
        signature = (
            normalized_tree(region),
            ids.index(tie["from"]), ids.index(tie["to"]),
            ids.index(feeder["from"]), risk, PROTOCOLS[risk][1],
        )
        require(repr(signature) not in signatures, "COPIED_INCIDENT_MECHANICS")
        signatures.add(repr(signature))
        per_region.append({
            "region_id": incident["region_id"],
            "incident_site_id": location,
            "risk_class": risk,
            "standby_source_branch": ids.index(tie["from"]),
            "standby_destination_branch": ids.index(tie["to"]),
            "managed_unserved_pressure_pu": PROTOCOLS[risk][1],
            "source_topology_hash": hashlib.sha256(
                repr(signature).encode("utf-8")).hexdigest(),
        })
    require(len(signatures) == 25 and transfer_live >= 5,
            "NOT_ENOUGH_DIFFERENTIABLE_RESPONSE_PATHS")
    return {
        "ok": True, "phase": "EXP015_A01",
        "qualification": HOLD,
        "distinct_electrical_recovery_chains": len(signatures),
        "source_pinned_incident_sites": len(keys),
        "five_different_hazard_protocols": len(PROTOCOLS),
        "original_first_or_join_incidents": len(keys),
        "source_live_critical_first_standby_opportunities": transfer_live,
        "source_managed_outage_fallbacks": len(keys),
        "original_campaign_or_rewards_edited": False,
        "physical_controller_steam_release_certified": False,
        "region_evidence": per_region,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=None)
    args = parser.parse_args()
    result = audit(*load())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("EXP015 A01 REGIONAL EMERGENCY SOURCE AUDIT: " +
          json.dumps({key: val for key, val in result.items()
                      if key != "region_evidence"}, sort_keys=True))


if __name__ == "__main__":
    main()
