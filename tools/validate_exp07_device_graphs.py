#!/usr/bin/env python3
"""EXP07 independent source audit for 200 host-operated expedition device graphs.

This is a read-only standard-library validator, not a human/controller or
physical collision qualification. It also exercises a separate reference
state machine to detect unsolvable prerequisite or recovery graphs.
"""
from __future__ import annotations

import json
from collections import Counter
from copy import deepcopy
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "scenes/expeditions/atlas.json"
EXP06 = ROOT / "scenes/expeditions/bespoke_encounters.json"
EXP07 = ROOT / "scenes/expeditions/bespoke_device_graphs.json"
ACTIONS = {
    "distribution": ("trace", "lockout", "phase_match", "bus_tie", "signoff", "stabilize"),
    "transport": ("survey", "brake", "align", "energize", "certify", "reroute"),
    "health": ("sample", "isolate", "flush", "transfer", "validate", "purge"),
    "commerce": ("trace", "seal", "balance", "supply", "audit", "bypass"),
    "waterworks": ("read", "shutoff", "bleed", "prime", "verify", "backwash"),
    "communications": ("scan", "shield", "synchronize", "route", "confirm", "retune"),
    "education": ("inspect", "partition", "calibrate", "restore", "check", "test"),
    "shelter": ("assess", "secure", "equalize", "handoff", "release", "reserve"),
}
ANCHORS = ("PANEL_WEST", "PANEL_SPUR", "R_WEST", "SW_EAST", "SW_GRID_SPUR", "SW_WEST_SPUR")
EVIDENCE = {"none", "west_inspected", "east_on", "west_restored"}


def load_inputs() -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    """Load only the three checked-in source files."""
    return tuple(json.loads(path.read_text(encoding="utf-8")) for path in
                 (ATLAS, EXP06, EXP07))  # type: ignore[return-value]


def validate(atlas: dict, encounters: dict, book: dict) -> dict:
    """Reject forged identities, duplicated targets, invalid DAGs and recovery gaps."""
    if (book.get("schema_version") != 1 or
        book.get("authority") != "EXP07_HOST_DEVICE_GRAPH" or
        book.get("atlas_revision") != atlas.get("revision")):
        raise ValueError("EXP07_BAD_BOOK_HEADER")
    levels = {v["id"]: v for v in atlas["levels"]}
    encounter_by_level = {v["level_id"]: v for v in encounters["entries"]}
    entries = book.get("entries")
    if len(levels) != 200 or len(encounter_by_level) != 200 or not isinstance(entries, list) or len(entries) != 200:
        raise ValueError("EXP07_INVALID_GRAPH_COUNT")
    seen: set[str] = set()
    keys: set[str] = set()
    operations: Counter[str] = Counter()
    total_nodes = 0
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("EXP07_NON_OBJECT_GRAPH")
        lid = entry.get("level_id")
        if lid not in levels or lid in seen or lid not in encounter_by_level:
            raise ValueError(f"EXP07_FOREIGN_OR_DUPLICATE_LEVEL {lid}")
        seen.add(lid)
        level, encounter = levels[lid], encounter_by_level[lid]
        site = entry.get("site")
        if site not in ACTIONS:
            raise ValueError(f"EXP07_UNKNOWN_SITE {lid}")
        expected = {
            "location_id": level["location_id"],
            "source_puzzle_identity": level["puzzle_identity"],
            "encounter_key": encounter["encounter_key"],
            "site": encounter["site"],
            "source_climate": encounter["source_climate"],
        }
        if any(entry.get(field) != value for field, value in expected.items()):
            raise ValueError(f"EXP07_SOURCE_DRIFT {lid}")
        key = entry.get("graph_key")
        if (not isinstance(key, str) or key != f'{lid}|{encounter["encounter_key"]}|{entry.get("graph_variant")}'
            or len(key) < 24 or key in keys):
            raise ValueError(f"EXP07_INVALID_GRAPH_KEY {lid}")
        keys.add(key)
        nodes = entry.get("nodes")
        if not isinstance(nodes, list) or not 5 <= len(nodes) <= 6:
            raise ValueError(f"EXP07_INVALID_NODE_COUNT {lid}")
        total_nodes += len(nodes)
        previous: set[str] = set()
        jam_nodes = []
        for index, node in enumerate(nodes):
            if not isinstance(node, dict):
                raise ValueError(f"EXP07_INVALID_NODE {lid}")
            ident = f'DV_{lid.removeprefix("LV_")}_{chr(65 + index)}'
            if (node.get("id") != ident or ident in previous or
                node.get("kind") != site or
                node.get("action") != ACTIONS[site][index] or
                node.get("anchor") != ANCHORS[index] or
                node.get("requires") not in EVIDENCE or
                not isinstance(node.get("depends_on"), list) or
                not isinstance(node.get("jam_on_early"), bool) or
                not isinstance(node.get("hazard_sensitive"), bool)):
                raise ValueError(f"EXP07_INVALID_NODE_PROPERTIES {lid}/{ident}")
            dependencies = node["depends_on"]
            if len(dependencies) != len(set(dependencies)) or any(dep not in previous for dep in dependencies):
                raise ValueError(f"EXP07_CYCLIC_OR_MISSING_PREDECESSOR {lid}/{ident}")
            if node["jam_on_early"]:
                jam_nodes.append(node)
                if index < 2 or not dependencies or node.get("recovery_after") not in previous:
                    raise ValueError(f"EXP07_BROKEN_RECOVERY {lid}/{ident}")
            elif node.get("recovery_after") != "":
                raise ValueError(f"EXP07_SPURIOUS_RECOVERY {lid}/{ident}")
            previous.add(ident)
            operations[node["action"]] += 1
        if len(jam_nodes) != 1 or jam_nodes[0]["recovery_after"] != nodes[1]["id"]:
            raise ValueError(f"EXP07_FAULT_ROUTE_MISSING {lid}")
        if nodes[-1]["requires"] != "west_restored" or nodes[3]["requires"] != "east_on":
            raise ValueError(f"EXP07_HOST_EVIDENCE_GUARD_MISSING {lid}")
        # The independent state-model must solve from a valid topological
        # ordering and demonstrate deterministic jam -> recovery for each graph.
        replay_reference(entry)
    if len(seen) != 200 or len(keys) != 200 or len(operations) < 20:
        raise ValueError("EXP07_MISSING_DIVERSITY_OR_DUPLICATE_ID")
    return {"ok": True, "levels": len(seen), "devices": total_nodes,
            "operations": len(operations), "five_node_graphs": sum(len(e["nodes"]) == 5 for e in entries),
            "six_node_graphs": sum(len(e["nodes"]) == 6 for e in entries)}


def replay_reference(graph: dict) -> None:
    """Exercise an intentionally separate pure-Python transition model."""
    nodes = graph["nodes"]
    states = {node["id"]: "idle" for node in nodes}
    fault = next(node for node in nodes if node["jam_on_early"])
    fid = fault["id"]
    # The premature operation is host-authorized but produces a jam.
    assert any(states[d] != "done" for d in fault["depends_on"])
    states[fid] = "jammed"
    assert states[fault["recovery_after"]] != "done"  # reset denied
    for node in nodes:
        if node["id"] == fid:
            assert states[node["recovery_after"]] == "done"
            states[fid] = "idle"  # reset after safe preparation
        assert all(states[d] == "done" for d in node["depends_on"])
        # In the reference replay, verified host facts are made available
        # before the guarded operation, not fabricated from client payloads.
        assert node["requires"] in EVIDENCE
        states[node["id"]] = "done"
    assert all(state == "done" for state in states.values())


def main() -> int:
    atlas, exp06, exp07 = load_inputs()
    result = validate(atlas, exp06, exp07)
    print("EXP07 SOURCE VERIFIED", json.dumps(result, sort_keys=True))
    print("HOLD: physical routes, human/controller, GPU, Steam and release")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
