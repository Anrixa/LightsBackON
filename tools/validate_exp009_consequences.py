#!/usr/bin/env python3
"""EXP009 independent, read-only source audit and deterministic cascade oracle.

No saves, credits, production contracts or user-facing progression are touched.
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "scenes/expeditions/atlas.json"
FAULTS = ROOT / "scenes/expeditions/fault_diagnostics.json"
CHAINS = ROOT / "scenes/expeditions/consequence_chains.json"
ANCHORS = ("PANEL_WEST", "PANEL_SPUR", "R_WEST")
SERVICES = {
    "distribution": ("Phase balancing relay", "Neighborhood distribution bus", "Priority feeder junction"),
    "transport": ("Traction interlock", "Crossing signal loop", "Passenger platform supply"),
    "health": ("Sterile-room pressure control", "Cold-chain supply", "Emergency treatment feeder"),
    "commerce": ("Load-sharing controller", "Archive preservation rail", "Market safety lighting"),
    "waterworks": ("Pump nonreturn valve", "Filtration control rail", "Flood barrier actuator"),
    "communications": ("Signal timing source", "Repeater reserve feed", "Emergency dispatch antenna"),
    "education": ("Campus control interlock", "Workshop safety rail", "Evacuation light circuit"),
    "shelter": ("Reserve transfer control", "Shelter heating feeder", "Emergency exit signage"),
}


def load_inputs() -> tuple[dict, dict, dict]:
    return tuple(json.loads(p.read_text(encoding="utf-8")) for p in (ATLAS, FAULTS, CHAINS))


def validate(atlas: dict, faults: dict, book: dict) -> dict:
    if (book.get("schema_version") != 1
            or book.get("authority") != "EXP009_HOST_CONSEQUENCES"
            or book.get("atlas_revision") != atlas.get("revision")):
        raise ValueError("EXP009_HEADER_INVALID")
    levels = {level["id"]: level for level in atlas["levels"]}
    diagnosed = {fault["level_id"]: fault for fault in faults["entries"]}
    entries = book.get("entries")
    if not isinstance(entries, list) or len(entries) != 200 or len(levels) != 200 or len(diagnosed) != 200:
        raise ValueError("EXP009_LEVEL_COUNT_INVALID")
    seen: set[str] = set()
    keys: set[str] = set()
    topologies: Counter[str] = Counter()
    domains: Counter[str] = Counter()
    targets: set[str] = set()
    for i, chain in enumerate(entries):
        if not isinstance(chain, dict):
            raise ValueError("EXP009_ENTRY_NOT_OBJECT")
        lid = chain.get("level_id")
        if lid not in diagnosed or lid not in levels or lid in seen:
            raise ValueError("EXP009_FOREIGN_OR_DUPLICATE_LEVEL")
        seen.add(lid)
        fault, level = diagnosed[lid], levels[lid]
        pins = {"location_id": level["location_id"],
                "source_puzzle_identity": level["puzzle_identity"],
                "scenario_key": fault["scenario_key"], "graph_key": fault["graph_key"],
                "site": fault["site"], "fault_class": fault["fault_class"]}
        if any(chain.get(k) != v for k, v in pins.items()):
            raise ValueError("EXP009_SOURCE_DRIFT")
        expected_topology = "fork" if i % 3 == 0 else "serial"
        if chain.get("topology") != expected_topology:
            raise ValueError("EXP009_TOPOLOGY_DRIFT")
        topologies[expected_topology] += 1
        domains[chain["site"]] += 1
        chain_key = fault["scenario_key"] + "|EXP009|" + expected_topology
        if chain.get("chain_key") != chain_key or chain_key in keys:
            raise ValueError("EXP009_KEY_INVALID")
        keys.add(chain_key)
        suffix = lid.removeprefix("LV_")
        console = "FC_" + suffix + "_CTRL"
        if chain.get("console") != console or chain.get("console_anchor") != "R_WEST" or type(chain.get("reserve")) is not int or chain["reserve"] != 1:
            raise ValueError("EXP009_CONSOLE_OR_RESERVE_INVALID")
        nodes = chain.get("nodes")
        if not isinstance(nodes, list) or len(nodes) != 3:
            raise ValueError("EXP009_NODE_COUNT_INVALID")
        if console in targets:
            raise ValueError("EXP009_DUPLICATE_TARGET")
        targets.add(console)
        for j, node in enumerate(nodes):
            if not isinstance(node, dict):
                raise ValueError("EXP009_NODE_NOT_OBJECT")
            id_ = f"FC_{suffix}_{j}"
            parent = "" if j == 0 else f"FC_{suffix}_{0 if expected_topology == 'fork' else j - 1}"
            if (node.get("id") != id_ or node.get("parent") != parent
                    or node.get("anchor") != ANCHORS[j]):
                raise ValueError("EXP009_NODE_TOPOLOGY_INVALID")
            if id_ in targets:
                raise ValueError("EXP009_DUPLICATE_TARGET")
            targets.add(id_)
            expected_threshold = 12 + ((i * 7 + j * 5 + fault["hold_ticks"]) % 24)
            if type(node.get("threshold_ticks")) is not int or node["threshold_ticks"] != expected_threshold:
                raise ValueError("EXP009_UNBOUNDED_OR_DRIFTED_THRESHOLD")
            if node.get("service") != SERVICES[chain["site"]][j]:
                raise ValueError("EXP009_SERVICE_IDENTITY_INVALID")
            if not isinstance(node.get("impact"), str) or len(node["impact"]) < 8:
                raise ValueError("EXP009_IMPACT_INVALID")
        replay_reference(chain)
    if len(keys) != 200 or len(topologies) != 2 or len(domains) != 8 or len(targets) != 800:
        raise ValueError("EXP009_COVERAGE_INCOMPLETE")
    export = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    if export.count("scenes/expeditions/consequence_chains.json") != 2:
        raise ValueError("EXP009_WINDOWS_EXPORT_MISSING")
    return {"ok": True, "levels": len(seen), "domains": len(domains),
            "topologies": dict(topologies), "linked_services": 600,
            "source_targets": len(targets)}


def replay_reference(chain: dict) -> None:
    """Independent oracle: pressure spreads deterministically; all losses recover.

    The engine implementation owns its actual counters and interlocks. Here the
    reference verifies forward-only dependencies, finite diversion and the
    existence of a repaired path after every node has suffered an incident.
    """
    states = {node["id"]: "dormant" for node in chain["nodes"]}
    root = chain["nodes"][0]
    states[root["id"]] = "at_risk"
    failures = 0
    for node in chain["nodes"]:
        id_ = node["id"]
        assert states[id_] == "at_risk", (chain["level_id"], id_)
        for _ in range(node["threshold_ticks"]):
            pass  # fixed host steps, not an external timestamp
        states[id_] = "failed"
        failures += 1
        for child in chain["nodes"]:
            if child["parent"] == id_:
                states[child["id"]] = "at_risk"
    assert failures == 3 and all(status == "failed" for status in states.values())
    for node in chain["nodes"]:
        assert not node["parent"] or states[node["parent"]] == "restored"
        states[node["id"]] = "restored"
    assert all(status == "restored" for status in states.values())
    reserve = chain["reserve"]
    assert reserve == 1 and reserve - 1 == 0
    assert len({node["id"] for node in chain["nodes"]}) == 3


def main() -> int:
    atlas, faults, chains = load_inputs()
    print("EXP009 SOURCE AUDIT", json.dumps(validate(atlas, faults, chains), sort_keys=True))
    print("HOLD: physical playability, human/controller, GPU/Steam, saves and production release")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
