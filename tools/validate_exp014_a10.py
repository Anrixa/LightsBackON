#!/usr/bin/env python3
"""EXP014 A10.1 independent cross-system provenance and scenario oracle.

Joins the real 200-level atlas to EXP05 OR-join routes, A02 contingencies,
A08 mechanical evidence graphs and A09 regional protected-feeder sources.
This is a reproducible SOURCE/HEADLESS design audit. It is not a claim that
200 physical levels, player traversal, hardware, Steam, saves or release pass.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from tools.validate_exp014_networks import (
    validate as audit_networks,
    unlabeled_tree_signature,
    dependencies,
)
from tools.validate_exp014_outcomes import parse_script as parse_risk_classes

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / "scenes" / "expeditions"
PATHS = {
    "atlas": DIR / "atlas.json",
    "campaign": DIR / "campaign_routes.json",
    "contingencies": DIR / "site_contingencies_exp014_a02.json",
    "investigations": DIR / "site_investigations_exp014_a08.json",
    "networks": DIR / "regional_networks_exp014_a09.json",
}
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
BRANCH_SLOTS = {
    "resilience_first": (0, 1, 3, 4, 6, 7),
    "critical_first": (0, 2, 3, 5, 6, 7),
}
EXPECTED_JOB_KINDS = (
    "investigation", "power_routing", "field_repair",
    "optional_discovery", "restoration",
)


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise ValueError("EXP014_A10_1_" + reason)


def read_sources() -> dict[str, dict]:
    return {key: json.loads(path.read_text(encoding="utf-8"))
            for key, path in PATHS.items()}


def canonical_sha(value: Any) -> str:
    """Immutable source-independent digest for cross-system evidence output."""
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"),
                         ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def investigation_schedule(spec: dict, mode: str) -> tuple:
    """Construct a real topological order; reject cycles and dead-end proofs."""
    nodes = spec.get("nodes")
    require(isinstance(nodes, list) and len(nodes) == (6 if mode == "forensic" else 7),
            "INVESTIGATION_NODE_COUNT")
    ids = [node.get("id") for node in nodes if isinstance(node, dict)]
    require(ids == [f"P{i}" for i in range(len(nodes))],
            "INVESTIGATION_NODE_IDS")
    remaining = {node["id"]: node for node in nodes}
    visited: set[str] = set()
    witness: list[tuple] = []
    total_cost = 0
    for _ in range(len(nodes)):
        ready = [node for node in nodes if node["id"] in remaining
                 and isinstance(node.get("requires"), list)
                 and all(dep in visited for dep in node["requires"])]
        require(bool(ready), "INVESTIGATION_CYCLE_OR_MISSING_PROOF")
        node = ready[0]
        require(node.get("station") in ("A", "B", "C")
                and isinstance(node.get("kind"), str)
                and isinstance(node.get("guard"), str)
                and type(node.get("cost")) is int
                and 0 <= node["cost"] <= 1, "INVESTIGATION_UNSUPPORTED_OPERATION")
        total_cost += node["cost"]
        witness.append((node["kind"], node["station"],
                        tuple(node["requires"]), node["guard"], node["cost"]))
        visited.add(node["id"])
        del remaining[node["id"]]
    require(not remaining and nodes[-1]["kind"] == "attest"
            and (1 <= total_cost <= 3 if mode == "forensic" else total_cost == 0),
            "INVESTIGATION_UNSOLVABLE_BUDGET")
    ancestry = {nodes[-1]["id"]}
    for node in reversed(nodes):
        if node["id"] in ancestry:
            ancestry.update(node["requires"])
    require(ancestry == set(ids), "INVESTIGATION_DECORATIVE_PROOF")
    return (spec.get("entry"), tuple(witness))


def energized_tree(region: dict, restored: set[str]) -> set[str]:
    """Source-only normal feeder traversal; no invented physical power flow."""
    live = {region["root_source_id"]} if region["root_source_id"] in restored else set()
    for _ in range(8):
        original = len(live)
        for edge in region["primary_feeders"]:
            if edge["from"] in live and edge["to"] in restored:
                live.add(edge["to"])
        if len(live) == original:
            break
    return live


def replay_branch(region: dict, campaign_nodes: dict, mode: str,
                  previous_finale: str | None) -> dict:
    """Exercise both original EXP05 OR-joint paths and bounded safe fallback.

    This is an abstract SOURCE reachability oracle, not an actual host replay.
    Each dispatch may choose a managed dark-service preparation; this avoids
    falsely asserting that its source feeder must already be physically live.
    """
    sites = [site["site_id"] for site in region["source_sites"]]
    restored = {previous_finale} if previous_finale else set()
    path = [sites[slot] for slot in BRANCH_SLOTS[mode]]
    dark_preparations = 0
    live_preparations = 0
    for site_id in path:
        predecessors = campaign_nodes[site_id]["requires_any"]
        require(not predecessors or any(item in restored for item in predecessors),
                "CAMPAIGN_BRANCH_DEADLOCK")
        live = energized_tree(region, restored)
        incoming = [edge for edge in region["primary_feeders"]
                    if edge["to"] == site_id]
        supply_ready = site_id == region["root_source_id"] or any(
            edge["from"] in live for edge in incoming)
        if supply_ready:
            live_preparations += 1
        else:
            # A09.3's "managed" preparation is an explicit debt-bearing
            # alternative to finite standby capacity, not a free energization.
            dark_preparations += 1
        restored.add(site_id)
    proof_id = region["strategies"][mode]["requires_receipt_site"]
    require(proof_id in restored, "STRATEGY_PROOF_UNREACHABLE")
    require(region["shelter_service_site"] in restored
            and len(path) == 6, "CAMPAIGN_FINALE_UNREACHABLE")
    return {
        "mode": mode,
        "sites": path,
        "strategy_receipt_site": proof_id,
        "live_preparations": live_preparations,
        "managed_outage_preparations": dark_preparations,
        "finale_restored": True,
        "physical_playability_verified": False,
    }


def audit(atlas: dict, campaign: dict, contingencies: dict,
          investigations: dict, networks: dict,
          risk_classes: dict[str, str]) -> dict:
    """Independent A10 cross-system audit; inputs injectable for mutation tests."""
    levels = atlas.get("levels")
    locations = atlas.get("locations")
    originals = contingencies.get("entries")
    proofs = investigations.get("entries")
    routes = campaign.get("nodes")
    regions = networks.get("regions")
    require(all(isinstance(v, list) for v in
                (levels, locations, originals, proofs, routes, regions)),
            "MISSING_SOURCE_COLLECTION")
    require(len(levels) == len(locations) == len(originals)
            == len(proofs) == len(routes) == 200 and len(regions) == 25,
            "CANONICAL_COVERAGE")
    require(campaign.get("authority") == "EXP05_HOST_RESTORATION_ONLY"
            and campaign.get("branch_policy") == "OR_JOIN_NON_EXCLUSIVE_REPLAYABLE"
            and investigations.get("authority") ==
            "EXP014_A08_HOST_INVESTIGATION_CHAINS"
            and networks.get("authority") ==
            "EXP014_A09_1_SOURCE_NETWORK_TOPOLOGIES_ONLY"
            and investigations.get("qualification") == QUALIFICATION
            and networks.get("qualification") == QUALIFICATION,
            "SOURCE_AUTHORITY")
    require(set(risk_classes) == {f"REG_{i:02d}" for i in range(1, 26)},
            "REGIONAL_RISK_COVERAGE")
    route_by_id = {node.get("level_id"): node for node in routes}
    require(len(route_by_id) == 200, "DUPLICATE_CAMPAIGN_NODE")
    tasks_seen: set[str] = set()
    lore_seen: set[str] = set()
    levels_seen: set[str] = set()
    locations_seen: set[str] = set()
    mechanical_fingerprints: set[str] = set()
    investigation_signatures = {"forensic": set(), "field": set()}
    per_region: list[dict] = []

    for region_idx, region in enumerate(regions):
        rid = f"REG_{region_idx + 1:02d}"
        source_region = atlas["regions"][region_idx]
        require(region.get("region_id") == rid == source_region.get("id")
                and region.get("risk_class") == risk_classes[rid],
                "REGION_RISK_OR_IDENTITY_SPLICE")
        sources = region.get("source_sites")
        require(isinstance(sources, list) and len(sources) == 8,
                "REGIONAL_SITE_COUNT")
        local_ids = [item.get("site_id") for item in sources]
        require(len(set(local_ids)) == 8, "DUPLICATE_REGIONAL_SITE")
        for slot in range(8):
            serial = region_idx * 8 + slot + 1
            lid = f"LV_{serial:03d}"
            location_id = f"LOC_{serial:03d}"
            level = levels[serial - 1]
            place = locations[serial - 1]
            old = originals[serial - 1]
            inquiry = proofs[serial - 1]
            node = routes[serial - 1]
            listed = sources[slot]
            required_tasks = [f"JOB_{serial:03d}_{idx}" for idx in range(1, 6)]
            jobs = level.get("tasks")
            require(isinstance(jobs, list) and len(jobs) == 5,
                    "SITE_TASK_CARDINALITY")
            ids = [job.get("id") for job in jobs]
            require(level.get("id") == lid == inquiry.get("level_id") ==
                    old.get("level_id") == node.get("level_id") ==
                    listed.get("site_id") and
                    location_id == place.get("id") == level.get("location_id") ==
                    inquiry.get("location_id") == old.get("location_id") ==
                    listed.get("location_id") and
                    rid == level.get("region_id") == inquiry.get("region_id") ==
                    old.get("region_id") == node.get("region_id") ==
                    place.get("district_id"), "CROSS_SYSTEM_IDENTITY_SPLICE")
            require(ids == required_tasks == old.get("source_task_ids") ==
                    inquiry.get("source_task_ids") ==
                    listed.get("source_task_ids"), "IMMUTABLE_TASK_CROSS_LINK")
            require([job.get("kind") for job in jobs] ==
                    list(EXPECTED_JOB_KINDS)
                    and [job.get("required") for job in jobs] ==
                    [True, True, True, False, True],
                    "TASK_AUTHORITY_OR_OPTIONALITY")
            require(node.get("requires_any") == dependencies(serial),
                    "OR_JOIN_REGRESSION")
            require(old.get("source_puzzle_identity") ==
                    inquiry.get("source_puzzle_identity") ==
                    level.get("puzzle_identity") and
                    old.get("worksite_encounter_key") ==
                    inquiry.get("worksite_encounter_key") and
                    old.get("targets") == inquiry.get("targets") and
                    old.get("source_route_actions") ==
                    inquiry.get("source_route_actions") and
                    old.get("source_risk") ==
                    inquiry.get("source_risk") ==
                    place.get("risk") == level.get("hazard"),
                    "MECHANICAL_SOURCE_SPLICE")
            require(inquiry.get("risk_class") == risk_classes[rid] and
                    listed.get("worksite_family") == place.get("archetype"),
                    "SITE_RISK_OR_FAMILY_SPLICE")
            collectible = level.get("collectible", {})
            lore = f"FIND_{serial:03d}"
            require(collectible.get("id") == lore and
                    collectible.get("discovery_task_id") == required_tasks[3] and
                    collectible.get("effect") == "LORE_ONLY_NO_POWER_OR_CREDITS",
                    "ORIGINAL_LORE_OR_REWARD_DRIFT")
            require(level.get("scoring_authority") == "PREVIEW_POINTS_ONLY",
                    "PREVIEW_REWARD_AUTHORITY")
            require(not tasks_seen.intersection(ids) and
                    lid not in levels_seen and location_id not in locations_seen and
                    lore not in lore_seen, "DUPLICATE_SOURCE_ID")
            tasks_seen.update(ids)
            levels_seen.add(lid)
            locations_seen.add(location_id)
            lore_seen.add(lore)
            branches = inquiry.get("branches")
            require(isinstance(branches, dict) and
                    set(branches) == {"forensic", "field"},
                    "INVESTIGATION_BRANCH_COVERAGE")
            branch_structure: dict[str, tuple] = {}
            for mode in ("forensic", "field"):
                spec = branches[mode]
                sig = investigation_schedule(spec, mode)
                require(sig not in investigation_signatures[mode],
                        "COSMETIC_INVESTIGATION_COLLISION_" + mode.upper())
                investigation_signatures[mode].add(sig)
                branch_structure[mode] = sig
            routes_source = old.get("routes", {})
            require(set(routes_source) == {"priority", "resilience"},
                    "CONTINGENCY_ROUTE_COVERAGE")
            structure = {
                "investigations": branch_structure,
                "contingencies": {
                    mode: [(step["mode"], step["guard"], step["failure"],
                            step["target"], step["support"], step["witness"])
                           for step in routes_source[mode]]
                    for mode in ("priority", "resilience")
                },
                "risk_family": inquiry["risk_class"],
                "task_mechanics": [job.get("mechanic") for job in jobs],
            }
            signature = canonical_sha(structure)
            require(signature not in mechanical_fingerprints,
                    "NONCOSMETIC_SCENARIO_COLLISION")
            mechanical_fingerprints.add(signature)
        prior_finale = (f"LV_{region_idx * 8:03d}" if region_idx else None)
        replay = [replay_branch(region, route_by_id, mode, prior_finale)
                  for mode in ("resilience_first", "critical_first")]
        local = [site["site_id"] for site in sources]
        parents = [local.index(edge["from"]) for edge in
                   region["primary_feeders"]]
        per_region.append({
            "region_id": rid,
            "risk": region["risk_class"],
            "primary_structure_sha256": canonical_sha(
                unlabeled_tree_signature(parents)),
            "branch_scenarios": replay,
        })

    require(len(tasks_seen) == 1000 and len(lore_seen) == 200 and
            len(mechanical_fingerprints) == 200 and
            all(len(signatures) == 200 for signatures in
                investigation_signatures.values()), "FULL_CONTENT_COVERAGE")
    topology_ids = {region["primary_structure_sha256"] for region in per_region}
    require(len(topology_ids) == 25, "REGIONAL_TOPOLOGY_COLLISION")
    upstream = audit_networks(atlas, campaign, investigations, networks)
    require(upstream["ok"] and upstream["primary_feeders"] == 175 and
            upstream["normally_open_standby_ties"] == 50,
            "NETWORK_ORIGINAL_SOURCE_GATE")
    scenarios = [path for region in per_region for path in region["branch_scenarios"]]
    require(len(scenarios) == 50 and
            all(path["finale_restored"] for path in scenarios),
            "BRANCH_SCENARIO_COVERAGE")
    return {
        "ok": True, "phase": "EXP014_A10_1",
        "authority": "SOURCE_ORACLE_NOT_PLAYABILITY_CERTIFICATION",
        "regions": len(per_region), "locations": len(locations_seen),
        "levels": len(levels_seen), "immutable_task_ids": len(tasks_seen),
        "original_lore_ids": len(lore_seen),
        "distinct_mechanical_source_fingerprints": len(mechanical_fingerprints),
        "distinct_investigation_source_graphs": {
            mode: len(sigs) for mode, sigs in investigation_signatures.items()},
        "distinct_unlabeled_regional_networks": len(topology_ids),
        "cross_system_campaign_branch_scenarios": len(scenarios),
        "branch_dispatch_source_visits": sum(len(x["sites"]) for x in scenarios),
        "abstract_managed_outage_preparations": sum(
            x["managed_outage_preparations"] for x in scenarios),
        "all_branch_scenarios_reach_finale": True,
        "original_save_and_credits_changed": False,
        "physical_playability_certified": False,
        "hardware_steam_release_certified": False,
        "source_fingerprint_sha256": canonical_sha({
            "mechanical_signatures": sorted(mechanical_fingerprints),
            "regional_topologies": sorted(topology_ids),
        }),
        "regions_evidence": per_region,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, help="Optional JSON evidence file")
    args = parser.parse_args()
    values = read_sources()
    classes, _ = parse_risk_classes()
    result = audit(**values, risk_classes=classes)
    output = json.dumps(result, sort_keys=True, indent=2, ensure_ascii=False)
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output + "\n", encoding="utf-8")
    summary = {k: v for k, v in result.items() if k != "regions_evidence"}
    print("EXP014 A10.1 CROSS-SYSTEM SOURCE AUDIT:",
          json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
