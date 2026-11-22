#!/usr/bin/env python3
"""Independent EXP014 A09.1 regional feeder-source and provenance audit.

This is a *source* audit, not a runtime electrical model, real-player test,
network authorization proof, hardware benchmark, or release certification.
Diversity is measured on unlabeled rooted feeder trees, ignoring site IDs,
names, risk prose, capacities, and every other numeric/cosmetic variation.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "scenes/expeditions/atlas.json"
CAMPAIGN = ROOT / "scenes/expeditions/campaign_routes.json"
PUZZLES = ROOT / "scenes/expeditions/site_investigations_exp014_a08.json"
BOOK = ROOT / "scenes/expeditions/regional_networks_exp014_a09.json"

AUTHORITY = "EXP014_A09_1_SOURCE_NETWORK_TOPOLOGIES_ONLY"
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
PROTECTION = {
    "depth": "water_isolation",
    "conductivity": "earth_fault_trip",
    "mechanical": "torque_interlock",
    "structure": "clearance_lockout",
    "weather": "surge_trip",
}
STRATEGY_NAMES = {"critical_first", "resilience_first"}


def require(condition: bool, reason: str) -> None:
    """Fail closed with a stable failure code for CI and mutation tests."""
    if not condition:
        raise ValueError("EXP014_A09_1_" + reason)


def is_int(value: Any, low: int, high: int) -> bool:
    return type(value) is int and low <= value <= high


def dependencies(serial: int) -> list[str]:
    """Exact EXP05 OR-join policy; preserve alternate-route replayability."""
    slot = (serial - 1) % 8
    base = serial - 1 - slot
    ref = lambda index: f"LV_{index:03d}"
    if slot == 0:
        return [ref(base)] if base else []
    if slot in (1, 2):
        return [ref(base + 1)]
    if slot == 3:
        return [ref(base + 2), ref(base + 3)]
    if slot in (4, 5):
        return [ref(base + 4)]
    if slot == 6:
        return [ref(base + 5), ref(base + 6)]
    return [ref(base + 7)]


def unlabeled_tree_signature(parents: list[int]) -> str:
    """Exact rooted-tree isomorphism signature (not merely a degree histogram).

    Sorting child encodings removes ordering and all site identities; even a
    relabeled or numerically padded duplicate produces the same signature.
    """
    children: list[list[int]] = [[] for _ in range(8)]
    for destination, parent in enumerate(parents, start=1):
        children[parent].append(destination)

    def encode(node: int) -> str:
        return "(" + "".join(sorted(encode(child) for child in children[node])) + ")"

    return encode(0)


def validate(atlas: dict, campaign: dict, puzzles: dict, book: dict) -> dict:
    require(book.get("schema_version") == 1
            and book.get("authority") == AUTHORITY
            and book.get("qualification") == QUALIFICATION
            and book.get("predecessor") == "EXP014_A08"
            and book.get("host_runtime_enabled") is False
            and book.get("legacy_campaign_contracts_unchanged") is True,
            "HEADER_OR_UNAUTHORIZED_RUNTIME_CLAIM")
    regions = book.get("regions")
    source_regions = atlas.get("regions")
    levels = atlas.get("levels")
    locations = atlas.get("locations")
    routes = campaign.get("nodes")
    investigations = puzzles.get("entries")
    require(all(isinstance(x, list) for x in
                (regions, source_regions, levels, locations, routes, investigations))
            and len(regions) == len(source_regions) == 25
            and len(levels) == len(locations) == len(routes) == len(investigations) == 200,
            "CANONICAL_COVERAGE")
    require(campaign.get("authority") == "EXP05_HOST_RESTORATION_ONLY"
            and campaign.get("branch_policy") == "OR_JOIN_NON_EXCLUSIVE_REPLAYABLE"
            and puzzles.get("authority") == "EXP014_A08_HOST_INVESTIGATION_CHAINS",
            "PREDECESSOR_AUTHORITY")

    global_sites: set[str] = set()
    global_jobs: set[str] = set()
    global_edges: set[str] = set()
    signatures: set[str] = set()
    protected_count = 0
    standby_count = 0
    for idx, (region, original_region) in enumerate(zip(regions, source_regions)):
        rid = f"REG_{idx + 1:02d}"
        require(isinstance(region, dict)
                and region.get("region_id") == rid == original_region.get("id")
                and region.get("region_name") == original_region.get("name")
                and region.get("environment_hazard") == original_region.get("hazard")
                and region.get("climate") == original_region.get("climate"),
                "REGION_SOURCE_SPLICE")
        source_puzzles = investigations[idx * 8:(idx + 1) * 8]
        risk = source_puzzles[0].get("risk_class")
        require(risk in PROTECTION
                and region.get("risk_class") == risk
                and all(p.get("risk_class") == risk for p in source_puzzles),
                "RISK_SOURCE_SPLICE")
        require(all(isinstance(region.get(field), str)
                    and len(region[field]) >= 8 for field in
                    ("network_note", "fault_signature", "recovery_procedure")),
                "MISSING_REGION_OPERATION_BRIEF")
        sites = region.get("source_sites")
        primary = region.get("primary_feeders")
        ties = region.get("standby_ties")
        require(isinstance(sites, list) and len(sites) == 8
                and isinstance(primary, list) and len(primary) == 7
                and isinstance(ties, list) and len(ties) == 2,
                "NETWORK_CARDINALITY")
        site_ids: list[str] = []
        for slot, node in enumerate(sites):
            serial = idx * 8 + slot + 1
            level, location, campaign_node, puzzle = (
                levels[serial - 1], locations[serial - 1],
                routes[serial - 1], investigations[serial - 1])
            expected_id = f"LV_{serial:03d}"
            expected_tasks = [f"JOB_{serial:03d}_{j}" for j in range(1, 6)]
            require(node.get("site_id") == expected_id == level.get("id")
                    == campaign_node.get("level_id") == puzzle.get("level_id")
                    and node.get("location_id") == level.get("location_id")
                    == location.get("id") == puzzle.get("location_id")
                    and level.get("region_id") == rid
                    == campaign_node.get("region_id") == puzzle.get("region_id")
                    and node.get("location_name") == location.get("name")
                    and node.get("worksite_family") == location.get("archetype")
                    and node.get("campaign_role") == campaign_node.get("role"),
                    "SITE_SOURCE_SPLICE")
            require(node.get("source_task_ids") == expected_tasks
                    == [task.get("id") for task in level.get("tasks", [])]
                    == puzzle.get("source_task_ids"),
                    "IMMUTABLE_TASK_SPLICE")
            require(campaign_node.get("requires_any") == dependencies(serial),
                    "EXISTING_OR_JOIN_DRIFT")
            require(expected_id not in global_sites
                    and not global_jobs.intersection(expected_tasks),
                    "DUPLICATE_SOURCE_SITE_OR_TASK")
            global_sites.add(expected_id)
            global_jobs.update(expected_tasks)
            site_ids.append(expected_id)

        require(region.get("root_source_id") == site_ids[0]
                and region.get("critical_service_site") == site_ids[2]
                and region.get("shelter_service_site") == site_ids[7]
                and region.get("reserve_anchor_site") == site_ids[5]
                and is_int(region.get("initial_reserve_pu"), 4, 16)
                and region["initial_reserve_pu"] % 2 == 0,
                "PRIORITY_ANCHOR_OR_RESERVE")
        parents: list[int] = []
        local_pairs: set[tuple[int, int]] = set()
        for slot, edge in enumerate(primary, start=1):
            require(edge.get("edge_id") == f"NET_{idx + 1:02d}_F{slot:02d}"
                    and edge["edge_id"] not in global_edges
                    and edge.get("kind") == "protected_feeder"
                    and edge.get("protection") == PROTECTION[risk]
                    and edge.get("normally_closed") is True
                    and is_int(edge.get("capacity_pu"), 4, 64)
                    and edge.get("to") == site_ids[slot]
                    and edge.get("from") in site_ids[:slot],
                    "PRIMARY_TREE_OR_PROTECTION")
            parent = site_ids.index(edge["from"])
            require((parent, slot) not in local_pairs, "DUPLICATE_FEEDER")
            parents.append(parent)
            local_pairs.add((parent, slot))
            global_edges.add(edge["edge_id"])
            protected_count += 1
        require(len(parents) == 7, "UNREACHABLE_SITE")
        shape = unlabeled_tree_signature(parents)
        require(shape not in signatures, "NONCOSMETIC_DUPLICATE_TOPOLOGY")
        signatures.add(shape)
        for slot, edge in enumerate(ties, start=1):
            require(edge.get("edge_id") == f"NET_{idx + 1:02d}_T{slot:02d}"
                    and edge["edge_id"] not in global_edges
                    and edge.get("kind") == "isolated_standby_tie"
                    and edge.get("interlock") == "break_before_make"
                    and edge.get("normally_closed") is False
                    and is_int(edge.get("capacity_pu"), 4, 64)
                    and edge.get("from") in site_ids
                    and edge.get("to") in site_ids,
                    "UNSAFE_STANDBY_TIE")
            source_index, dest_index = (
                site_ids.index(edge["from"]), site_ids.index(edge["to"]))
            require(source_index < dest_index and dest_index in (5, 7)
                    and (source_index, dest_index) not in local_pairs,
                    "CYCLE_OR_PARALLEL_TIE")
            global_edges.add(edge["edge_id"])
            local_pairs.add((source_index, dest_index))
            standby_count += 1
        strategies = region.get("strategies")
        require(isinstance(strategies, dict)
                and set(strategies) == STRATEGY_NAMES,
                "MISSING_STRATEGY")
        critical = strategies["critical_first"]
        resilient = strategies["resilience_first"]
        require(critical.get("requires_receipt_site") == site_ids[2]
                and critical.get("target_site") == site_ids[7]
                and critical.get("priority") == "life_safety"
                and resilient.get("requires_receipt_site") == site_ids[1]
                and resilient.get("target_site") == site_ids[5]
                and resilient.get("priority") == "reserve_integrity"
                and all(isinstance(s.get("intended_tradeoff"), str)
                        and len(s["intended_tradeoff"]) >= 25
                        for s in (critical, resilient)),
                "STRATEGY_SOURCE_OR_TRADEOFF")

    require(len(signatures) == 25 and len(global_sites) == 200
            and len(global_jobs) == 1000 and protected_count == 175
            and standby_count == 50 and len(global_edges) == 225,
            "FULL_SOURCE_COVERAGE")
    return {
        "ok": True,
        "regions": len(regions),
        "unique_unlabeled_rooted_primary_topologies": len(signatures),
        "source_sites": len(global_sites),
        "immutable_job_ids": len(global_jobs),
        "primary_feeders": protected_count,
        "normally_open_standby_ties": standby_count,
        "host_runtime_enabled": False,
        "human_controller_certified": False,
    }


def load_and_validate() -> dict:
    def read(path: Path) -> dict:
        return json.loads(path.read_text(encoding="utf-8"))
    return validate(read(ATLAS), read(CAMPAIGN), read(PUZZLES), read(BOOK))


if __name__ == "__main__":
    print(json.dumps(load_and_validate(), sort_keys=True))
