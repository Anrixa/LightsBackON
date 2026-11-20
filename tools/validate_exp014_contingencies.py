#!/usr/bin/env python3
"""EXP014 A02: independent source/puzzle-structure and host-timing audit.

Reuses immutable EXP012/EXP013 authored sites. New source data is an opt-in
contingency expansion, not 200 physically certified 3D levels. Mechanical
signatures deliberately EXCLUDE all action titles, narrative and timer values.
"""
from __future__ import annotations

from collections import Counter
import json
from pathlib import Path

if __package__:
    from tools.validate_exp012_worksites import load_inputs
    from tools.validate_exp014_composition import source_entries, structural_route
else:
    from validate_exp012_worksites import load_inputs
    from validate_exp014_composition import source_entries, structural_route

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "scenes/expeditions/site_contingencies_exp014_a02.json"
PRESETS = ROOT / "export_presets.cfg"
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
MODES = {"quorum", "reserve_lease", "isolation_mesh"}
GUARDS = {"load_balanced", "supplies_ready", "cascade_stable", "fault_clear"}
FAILURES = {"step", "backtrack", "restart"}
FIELDS = {"mode", "action", "target", "support", "witness", "guard",
          "failure", "dwell_ticks", "window_ticks", "witness_gap_ticks"}


def require(ok: bool, code: str) -> None:
    if not ok:
        raise ValueError(code)


def read_book() -> dict:
    return json.loads(SOURCE.read_text(encoding="utf-8"))


def mechanic_signature(entry: dict, route: str) -> tuple:
    reverse = {value: key for key, value in entry["targets"].items()}
    steps = entry["routes"][route]
    return tuple((s["mode"], reverse[s["target"]], reverse[s["support"]],
                  reverse[s["witness"]], s["guard"], s["failure"])
                 for s in steps)


def next_recovery_index(scope: str, index: int) -> int:
    require(scope in FAILURES and 0 <= index < 3, "EXP014_RECOVERY_SCOPE")
    return 0 if scope == "restart" else max(0, index - 1) if scope == "backtrack" else index


def replay_oracle(entry: dict, route: str) -> dict:
    """Independent bounded clock model for each exact source procedure.

    Client-supplied elapsed time cannot enter this oracle. Operate starts,
    10Hz host dwell, first station, witness gap and settling are different
    transitions. This checks every route has a finite safe host-only replay.
    """
    clock = 0
    actions = 0
    for index, step in enumerate(entry["routes"][route]):
        require(step["target"] != step["support"] != step["witness"] and
                step["target"] != step["witness"], "EXP014_ROUTING_DEADLOCK")
        # A start command, then a host-owned dwell, then the support action.
        actions += 2
        clock += step["dwell_ticks"]
        # Four real guard preflights: load-stability hold, stock acknowledgment,
        # relay ping, or independent fault-clearance probe. Each consumes
        # three host ticks; the latter three add one verified station action.
        clock += 3
        if step["guard"] != "load_balanced":
            actions += 1
        # The witness cannot arrive in the same tick as the first station.
        clock += step["witness_gap_ticks"]
        actions += 1
        # Quorum seals after two ticks, reserve lease after four and
        # isolation mesh after three host ticks. No client clock parameter.
        settle = {"quorum": 2, "reserve_lease": 4, "isolation_mesh": 3}[step["mode"]]
        clock += settle
        actions += 1
        require(step["witness_gap_ticks"] + settle < step["window_ticks"],
                "EXP014_DEADLINE_UNSOLVABLE")
        require(0 <= next_recovery_index(step["failure"], index) <= index,
                "EXP014_UNRECOVERABLE_FAILURE")
    return {"complete": True, "steps": 3, "actions": actions, "host_ticks": clock}


def validate(atlas: dict, previous: list[dict], source: dict,
             presets: str | None = None) -> dict:
    require(isinstance(source, dict) and source.get("schema_version") == 1 and
            source.get("authority") == "EXP014_A02_HOST_CONTINGENCY" and
            source.get("atlas_revision") == atlas["revision"] and
            source.get("qualification") == QUALIFICATION, "EXP014_HEADER")
    entries = source.get("entries")
    require(type(entries) is list and len(entries) == len(previous) == 200,
            "EXP014_SOURCE_COVERAGE")
    fingerprints: Counter[tuple] = Counter()
    regions = set()
    observed_modes = set()
    observed_guards = set()
    actions = 0
    steps = 0
    for n, (entry, original, level) in enumerate(
            zip(entries, previous, atlas["levels"]), start=1):
        require(type(entry) is dict and type(original) is dict,
                "EXP014_SOURCE_TYPE")
        for key in ("level_id", "location_id", "region_id", "source_title",
                    "source_risk", "source_climate", "source_puzzle_identity",
                    "source_task_ids", "worksite_encounter_key", "targets",
                    "recovery_target", "qualification"):
            require(entry.get(key) == original.get(key),
                    "EXP014_SOURCE_DRIFT_" + key)
        require(entry["level_id"] == f"LV_{n:03d}" and
                entry["region_id"] == f"REG_{(n - 1) // 8 + 1:02d}" and
                entry["source_task_ids"] == [task["id"] for task in level["tasks"]],
                "EXP014_TASK_ID_DRIFT")
        require(entry.get("intervention_title") == original["title"] and
                entry.get("stakes") == original["stakes"],
                "EXP014_SOURCE_STAKES_DRIFT")
        require(entry["risk_guard"] in GUARDS, "EXP014_RISK_GUARD")
        regions.add(entry["region_id"])
        target_ids = set(original["targets"].values())
        for route in ("priority", "resilience"):
            old_actions = [s["action"] for s in original["routes"][route]]
            require(entry["source_route_actions"][route] == old_actions,
                    "EXP014_ACTION_PIN_DRIFT")
            procedures = entry["routes"][route]
            require(type(procedures) is list and len(procedures) == 3,
                    "EXP014_PROCEDURE_COUNT")
            for procedure in procedures:
                require(type(procedure) is dict and set(procedure) == FIELDS,
                        "EXP014_PROCEDURE_SHAPE")
                require(procedure["mode"] in MODES and
                        procedure["guard"] in GUARDS and
                        procedure["failure"] in FAILURES,
                        "EXP014_UNKNOWN_MECHANIC")
                roles = (procedure["target"], procedure["support"],
                         procedure["witness"])
                require(set(roles) == target_ids and len(set(roles)) == 3,
                        "EXP014_FORGED_STATION")
                require(procedure["action"].startswith("contingency_") and
                        procedure["action"].removeprefix("contingency_")
                        in old_actions, "EXP014_FORGED_ACTION")
                for field, minimum, maximum in [
                    ("dwell_ticks", 6, 24), ("window_ticks", 40, 240),
                    ("witness_gap_ticks", 3, 8)]:
                    value = procedure[field]
                    require(type(value) is int and minimum <= value <= maximum,
                            "EXP014_UNSAFE_CLOCK_" + field)
                observed_modes.add(procedure["mode"])
                observed_guards.add(procedure["guard"])
                steps += 1
            oracle = replay_oracle(entry, route)
            require(oracle["complete"] and oracle["actions"] == 12 and
                    oracle["steps"] == 3 and
                    12 <= oracle["actions"] <= 15,
                    "EXP014_REPLAY_DEADLOCK")
            actions += oracle["actions"]
        fingerprint = (
            structural_route(original, "priority"),
            structural_route(original, "resilience"),
            mechanic_signature(entry, "priority"),
            mechanic_signature(entry, "resilience"),
        )
        fingerprints[fingerprint] += 1
    require(len(regions) == 25 and observed_modes == MODES and
            observed_guards == GUARDS and steps == 1200 and
            4800 <= actions <= 6000,
            "EXP014_MECHANIC_COVERAGE")
    require(len(fingerprints) >= 150 and max(fingerprints.values()) <= 8,
            "EXP014_NONCOSMETIC_DIVERSITY_GATE")
    if presets is None:
        presets = PRESETS.read_text(encoding="utf-8")
    require(presets.count("scenes/expeditions/site_contingencies_exp014_a02.json") == 2,
            "EXP014_EXPORT_SOURCE_MISSING")
    return {
        "ok": True, "sites": 200, "regions": 25, "routes": 400,
        "contingency_steps": steps, "host_action_transitions": actions,
        "baseline_action_floor": 4800,
        "new_host_mechanic_modes": sorted(observed_modes),
        "distinct_mechanical_route_pairs": len(fingerprints),
        "maximum_reused_structure": max(fingerprints.values()),
        "original_atlas_task_ids_preserved": 1000,
        "action_names_and_timers_ignored_in_uniqueness": True,
        "qualification": QUALIFICATION,
        "physical_playability_certified": False,
        "release_certified": False,
    }


if __name__ == "__main__":
    atlas, _, _ = load_inputs()
    print("EXP014 A02 SOURCE/RECOVERY AUDIT:",
          json.dumps(validate(atlas, source_entries(), read_book()), sort_keys=True))
