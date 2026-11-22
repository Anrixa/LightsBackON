#!/usr/bin/env python3
"""EXP015 A12.1 — original-tree anchor recovery oracle (source/headless only).

Independent Python checks the 25 source-authored regional primary paths,
including the two real slot-5 interruptions. No fake restoration, power,
multiplayer, persistence, payout or human-playability claim is made here.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Any

SOURCE = Path(__file__).resolve().parents[1] / "scenes" / "expeditions" / "regional_networks_exp014_a09.json"
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
ORIGINAL_DARK_REGION_NUMBERS = (11, 25)
BASE_SLOTS = (1, 2, 3, 4, 6, 7)


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError("EXP015_A12_" + code)


def source_book() -> dict[str, Any]:
    return json.loads(SOURCE.read_text(encoding="utf-8"))


def route(region: dict[str, Any]) -> tuple[list[str], list[str]]:
    sites = region["source_sites"]
    ids = [s["site_id"] for s in sites]
    root = region["root_source_id"]
    anchor = region["reserve_anchor_site"]
    require(len(ids) == len(set(ids)) == 8 and root == ids[0] and
            anchor in ids and region["shelter_service_site"] == ids[7],
            "ORIGINAL_SITES")
    require(all(len(s["source_task_ids"]) == 5 for s in sites),
            "ORIGINAL_TASK_IDS")
    feeders = region["primary_feeders"]
    require(len(feeders) == 7, "ORIGINAL_FEEDER_COUNT")
    incoming: dict[str, dict[str, Any]] = {}
    edge_ids: set[str] = set()
    for feeder in feeders:
        key, start, end = (feeder[x] for x in ("edge_id", "from", "to"))
        require(key not in edge_ids and start in ids and end in ids and
                start != end and end != root and end not in incoming and
                feeder["kind"] == "protected_feeder" and
                feeder["normally_closed"] is True, "NONORIGINAL_TREE_EDGE")
        edge_ids.add(key)
        incoming[end] = feeder
    require(len(incoming) == 7 and set(incoming) == set(ids) - {root},
            "ORIGINAL_TREE_INBOUND")
    # Validate the whole original tree, not just the reserve-anchor route.
    for node in ids:
        cursor, seen = node, set()
        while cursor != root:
            require(cursor in incoming and cursor not in seen,
                    "CYCLE_OR_DISCONNECTED_ORIGINAL_TREE")
            seen.add(cursor)
            cursor = incoming[cursor]["from"]
    nodes, edges = [anchor], []
    while nodes[-1] != root:
        edge = incoming[nodes[-1]]
        edges.append(edge["edge_id"])
        nodes.append(edge["from"])
    nodes.reverse()
    edges.reverse()
    return nodes, edges


def audit(book: dict[str, Any]) -> dict[str, Any]:
    regions = book.get("regions", [])
    require(book.get("qualification") == QUALIFICATION and
            len(regions) == 25, "SOURCE_AUTHORITY")
    results: list[dict[str, Any]] = []
    signatures: set[str] = set()
    region_ids: set[str] = set()
    dark: list[int] = []
    for index, region in enumerate(regions):
        number = index + 1
        require(region["region_id"] not in region_ids, "DUPLICATE_REGION")
        region_ids.add(region["region_id"])
        nodes, edges = route(region)
        original = {f"LV_{index * 8 + slot:03d}" for slot in BASE_SLOTS}
        missing = [site for site in nodes if site not in original]
        # With the genuine receipt fixture, only original intermediate nodes
        # can block the anchor; never mark those dark anchors energized.
        if missing:
            dark.append(number)
        require(len(edges) == len(nodes) - 1 and
                nodes[0] == region["root_source_id"] and
                nodes[-1] == region["reserve_anchor_site"],
                "ORIGINAL_ANCHOR_PATH")
        signature = hashlib.sha256(json.dumps(
            {"region": region["region_id"], "nodes": nodes, "edges": edges},
            sort_keys=True).encode("utf-8")).hexdigest()
        require(signature not in signatures, "DUPLICATE_TOPOLOGY_IDENTITY")
        signatures.add(signature)
        results.append({"region": number, "region_id": region["region_id"],
                        "source_root": nodes[0], "original_anchor": nodes[-1],
                        "original_site_path": nodes, "original_feeder_path": edges,
                        "missing_original_receipts": missing,
                        "source_sha256": signature, "source_only": True})
        print(f"EXP015_A12_SOURCE {number:02d}/25 root={nodes[0]} "
              f"anchor={nodes[-1]} path={len(edges)} "
              f"missing_receipts={','.join(missing) if missing else 'none'}")
    require(tuple(dark) == ORIGINAL_DARK_REGION_NUMBERS,
            "BASELINE_UPSTREAM_DARK_DRIFT")
    return {"ok": True, "phase": "EXP015_A12_1",
            "source_regions": len(results), "rooted_original_paths": len(results),
            "baseline_dark_region_numbers": dark, "original_route_evidence": results,
            "host_recovery_implemented": False,
            "qualification": QUALIFICATION}


def main() -> None:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--report", type=Path)
    args = cli.parse_args()
    result = audit(source_book())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    print("EXP015_A12_1_ORIGINAL_ANCHOR_PATHS=PASS paths=25 dark=2")


if __name__ == "__main__":
    main()
