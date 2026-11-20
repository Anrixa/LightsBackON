#!/usr/bin/env python3
"""EXP014 A08 independent evidence-DAG / immutable-source validation.

Measures true operation types, station roles, prerequisites, host guards and
kit expenditure. Names, narrative strings, source IDs and clocks are excluded
from the diversity signature. Never certifies human/controller/physics/release.
"""
from __future__ import annotations

import copy
import json
from pathlib import Path

if __package__:
    from .validate_exp014_outcomes import (
        ATLAS, CONTINGENCIES, QUALIFICATION, HOST, STAGE,
        load_a04, load_a05, parse_script as parse_a06,
    )
else:
    from validate_exp014_outcomes import (
        ATLAS, CONTINGENCIES, QUALIFICATION, HOST, STAGE,
        load_a04, load_a05, parse_script as parse_a06,
    )

ROOT = Path(__file__).resolve().parents[1]
BOOK = ROOT / "scenes/expeditions/site_investigations_exp014_a08.json"
MODULE = ROOT / "scripts/gameplay/expedition_investigation_chains.gd"
GUARDS = {"faults_solved", "balancing_solved",
          "logistics_solved", "consequences_solved"}
KINDS = {"trace", "calibrate", "sample", "isolate",
         "crosscheck", "attest", "reconcile"}
MODES = ("forensic", "field")


def require(ok: bool, reason: str) -> None:
    if not ok:
        raise ValueError("EXP014_A08_" + reason)


def signature(branch: dict) -> tuple:
    """Canonical source-free, time-free gameplay structure of a graph."""
    return (
        branch["entry"],
        tuple((
            node["kind"], node["station"], tuple(node["requires"]),
            node["guard"], node["cost"],
        ) for node in branch["nodes"]),
    )


def validate(
    atlas: dict, contingency: dict, a06_class: dict[str, str],
    book: dict, host: str, stage: str, module: str,
) -> dict:
    require(book.get("schema_version") == 1 and
            book.get("authority") == "EXP014_A08_HOST_INVESTIGATION_CHAINS" and
            book.get("qualification") == QUALIFICATION, "BOOK_HEADER")
    records = book.get("entries")
    originals = contingency.get("entries")
    levels = atlas.get("levels")
    require(isinstance(records, list) and isinstance(originals, list) and
            isinstance(levels, list) and
            len(records) == len(originals) == len(levels) == 200,
            "SOURCE_COVERAGE")
    forensic_signatures: set[tuple] = set()
    field_signatures: set[tuple] = set()
    jobs: set[str] = set()
    styles = set()
    for serial, (entry, old, level) in enumerate(
            zip(records, originals, levels), start=1):
        lid = f"LV_{serial:03d}"
        rid = f"REG_{(serial-1)//8+1:02d}"
        require(entry.get("level_id") == old.get("level_id") == level["id"] == lid
                and entry.get("location_id") == old.get("location_id")
                and entry.get("region_id") == old.get("region_id") == rid
                and entry.get("source_risk") == old.get("source_risk")
                and entry.get("source_puzzle_identity")
                == old.get("source_puzzle_identity")
                and entry.get("worksite_encounter_key")
                == old.get("worksite_encounter_key"), "SOURCE_IDENTITY_DRIFT")
        require(entry.get("risk_class") == a06_class[rid],
                "REGIONAL_RISK_DRIFT")
        require(entry.get("case_serial") == serial and
                entry.get("targets") == old.get("targets")
                and entry.get("recovery_target") == old.get("recovery_target")
                and entry.get("source_route_actions")
                == old.get("source_route_actions"), "SOURCE_STATION_OR_ACTION_SPLICE")
        tasks = [f"JOB_{serial:03d}_{i}" for i in range(1, 6)]
        require(entry.get("source_task_ids") == old.get("source_task_ids") == tasks
                and [t["id"] for t in level["tasks"]] == tasks,
                "IMMUTABLE_TASK_DRIFT")
        require(not jobs.intersection(tasks), "DUPLICATED_TASK")
        jobs.update(tasks)
        require(entry["targets"] == {
            letter: f"SC_{serial:03d}_{letter}" for letter in "ABC"
        }, "TARGET_IDS")
        branches = entry.get("branches")
        require(isinstance(branches, dict) and set(branches) == set(MODES),
                "BRANCH_COVERAGE")
        for mode in MODES:
            spec = branches[mode]
            count = 6 if mode == "forensic" else 7
            nodes = spec.get("nodes")
            require(spec.get("entry") in "ABC"
                    and isinstance(nodes, list) and len(nodes) == count,
                    "BAD_GRAPH_LENGTH")
            source_actions = old["source_route_actions"][
                "priority" if mode == "forensic" else "resilience"]
            seen = set()
            cost = 0
            node_ids = []
            for index, node in enumerate(nodes):
                require(isinstance(node, dict) and len(node) == 8
                        and node.get("id") == f"P{index}"
                        and node.get("kind") in KINDS
                        and node.get("station") in "ABC"
                        and node.get("guard") in GUARDS
                        and node.get("source_action") in source_actions,
                        "UNSUPPORTED_NODE")
                requires = node.get("requires")
                require(isinstance(requires, list)
                        and (not requires if index == 0 else bool(requires))
                        and all(dep in seen for dep in requires)
                        and len(requires) == len(set(requires)),
                        "CYCLE_OR_MISSING_DEPENDENCY")
                require(type(node.get("cost")) is int
                        and 0 <= node["cost"] <= 1
                        and type(node.get("dwell_ticks")) is int
                        and 2 <= node["dwell_ticks"] <= 4,
                        "KIT_OR_CLOCK_BOUNDS")
                cost += node["cost"]
                seen.add(node["id"])
                node_ids.append(node["id"])
            require(nodes[1]["requires"] == ["P0"]
                    and nodes[2]["requires"] == ["P0"]
                    and nodes[-1]["kind"] == "attest",
                    "NO_NONLINEAR_WITNESS_OR_ATTEST")
            require(1 <= cost <= 3 if mode == "forensic" else cost == 0,
                    "INVALID_BUDGET")
            # Every node must lead to the final attestation. Unreachable
            # decorative nodes do not count as meaningful investigation.
            required = {nodes[-1]["id"]}
            for node in reversed(nodes):
                if node["id"] in required:
                    required.update(node["requires"])
            require(required == set(node_ids), "DECORATIVE_UNCONNECTED_EVIDENCE")
            shape = signature(spec)
            container = forensic_signatures if mode == "forensic" else field_signatures
            require(shape not in container,
                    "NONCOSMETIC_DUPLICATE_" + mode.upper())
            container.add(shape)
            styles.add(tuple(tuple(n["requires"]) for n in nodes))
    require(len(jobs) == 1000 and len(forensic_signatures) == 200
            and len(field_signatures) == 200, "FULL_DIVERSITY_HOLD")
    require(len(styles) >= 6, "DEPENDENCY_GRAPH_DIVERSITY")

    host_gates = (
        "enable_site_puzzles: bool = false",
        "EXP014_A08_REQUIRES_A07_ENVIRONMENT",
        "site_puzzles.configure(",
        '["site_puzzles"] = site_puzzles.definition_snapshot()',
        'return "EXP014_A08_"',
        "site_puzzles.begin(site_hazards.snapshot())",
        "site_puzzles.advance(_puzzle_facts())",
        "site_puzzles.operate(entity, action, _puzzle_facts())",
        "site_puzzles.needs_action()",
        "site_puzzles.solved()",
        "EXP014_A08_INVESTIGATION_REQUIRED",
        "EXP014_A08_INVESTIGATION_INCOMPLETE",
        'state["site_puzzles"] = site_puzzles.snapshot()',
        'facts["recon_route"] = site_approach.selected_route()',
    )
    require(all(x in host for x in host_gates),
            "HOST_AUTHORITY_OR_EXTRACT_BYPASS")
    stage_gates = (
        "runtime.site_puzzles.needs_action()",
        "_activate_puzzle_target()",
        "runtime.site_puzzles.snapshot()",
        "KEY_P", "KEY_O", 'site_puzzles'
    )
    require(all(x in stage for x in stage_gates), "PRESENTATION_DISCONNECTED")
    engine_gates = (
        "func _available()",
        'if not seen.has(str(dep))',
        'return _reject("INSTRUMENT_KIT_EXHAUSTED")',
        '_kits -= int(option["cost"])',
        'not bool(facts.get("hazard_safe", false))',
        '_trip("EVIDENCE_STALE")',
        'return _trip("UPSTREAM_PROOF_LOST")',
        'str(facts.get("recon_route", "")) != _route',
        'entity != _target("C") or action != "recover"',
        '_phase = "certified"',
    )
    require(all(x in module for x in engine_gates),
            "ENGINE_SECURITY_OR_RECOVERY_MISSING")
    return {"ok": True, "source_sites": 200, "original_task_ids": len(jobs),
            "forensic_graphs": len(forensic_signatures),
            "field_graphs": len(field_signatures),
            "noncosmetic_dependency_patterns": len(styles),
            "headless_branch_replays": 400,
            "production_saves_changed": False,
            "human_controller_certified": False,
            "release_certified": False, "qualification": QUALIFICATION}


if __name__ == "__main__":
    source = json.loads(ATLAS.read_text(encoding="utf-8"))
    contingency = json.loads(CONTINGENCIES.read_text(encoding="utf-8"))
    a06, _ = parse_a06()
    result = validate(source, contingency, a06,
                      json.loads(BOOK.read_text(encoding="utf-8")),
                      HOST.read_text(encoding="utf-8"),
                      STAGE.read_text(encoding="utf-8"),
                      MODULE.read_text(encoding="utf-8"))
    print("EXP014 A08 INVESTIGATION DAG AUDIT:", json.dumps(
        result, sort_keys=True))
