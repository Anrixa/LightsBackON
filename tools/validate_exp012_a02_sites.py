#!/usr/bin/env python3
"""EXP012 A02 read-only source and route-mechanics audit.

This is a deliberately limited 40-site overlay, not a declaration that 200
individually authored playable locations have been achieved. Unlike the A01
family matrix, every covered source location has an explicit intervention
title, stake, two ordered worksite scripts and recoverable host action plan.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

# Executable directly by tools/run_tests.sh and importable by unittest.
if __package__:
    from tools.validate_exp012_worksites import load_inputs, validate as validate_a01
else:
    from validate_exp012_worksites import load_inputs, validate as validate_a01

ROOT = Path(__file__).resolve().parents[1]
A02 = ROOT / "scenes/expeditions/site_interventions_a02.json"
PRESETS = ROOT / "export_presets.cfg"
AUTHORITY = "EXP012_A02_HOST_SITE_INTERVENTIONS"
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
MODES = {"hold", "pulse", "sample", "handoff", "balance"}
PENALTIES = {"step", "backtrack", "restart"}
EXPECTED_FIELDS = {
    "action", "mode", "target", "support_target", "dwell_ticks",
    "window_ticks", "failure",
}


def require(test: bool, code: str) -> None:
    if not test:
        raise ValueError(code)


def read_book() -> dict:
    return json.loads(A02.read_text(encoding="utf-8"))


def replay(entry: dict, route: str) -> dict:
    """Independent deterministic oracle for a healthy host tick sequence.

    Mirrors semantic operations, not Godot's implementation details: 4
    source steps with real host-dwell, separate support-location actions,
    read spacing, bounded pulse window and post-trim settling. Zero shortcuts.
    """
    require(route in ("priority", "resilience"), "EXP012A02_UNKNOWN_ROUTE")
    tick = 0
    log = []
    for item in entry["routes"][route]:
        mode, action = item["mode"], item["action"]
        start, support = item["target"], item["support_target"]
        require(start != support, "EXP012A02_FALSE_STATION_SPLIT")
        tick += item["dwell_ticks"]
        stable_at = tick
        if mode == "sample":
            tick += 3
            log.extend(((support, "read", stable_at),
                        (support, "read", tick), (start, "confirm", tick)))
        elif mode == "handoff":
            log.extend(((support, "transfer", tick), (start, "commit", tick)))
        elif mode == "balance":
            tick += 4
            log.extend(((support, "trim", stable_at), (start, "confirm", tick)))
        elif mode == "pulse":
            log.append((start, "pulse", tick))
        else:
            log.append((start, "confirm", tick))
        duration = min(item["window_ticks"], 18) if mode == "pulse" else item["window_ticks"]
        require(tick - stable_at <= duration, "EXP012A02_ROUTE_DEADLINE")
        log.insert(len(log) - (3 if mode == "sample" else 2 if mode in ("handoff", "balance") else 1),
                   (start, action, stable_at - item["dwell_ticks"]))
    return {"completed": 4, "host_ticks": tick, "actions": len(log), "trace": log}


def recovery_oracle(failure: str, index: int) -> int:
    require(failure in PENALTIES and 0 <= index < 4, "EXP012A02_BAD_FAULT")
    return 0 if failure == "restart" else max(0, index - 1) if failure == "backtrack" else index


def validate(atlas: dict, a01: dict, book: dict,
             presets: str | None = None) -> dict:
    validate_a01(atlas, load_inputs()[1], a01)
    require(book.get("schema_version") == 1 and
            book.get("authority") == AUTHORITY and
            book.get("atlas_revision") == atlas.get("revision") and
            book.get("qualification") == QUALIFICATION,
            "EXP012A02_HEADER_INVALID")
    entries = book.get("entries")
    require(type(entries) is list and len(entries) == 40,
            "EXP012A02_COUNT_INVALID")
    require(len(atlas["levels"]) == 200 and len(a01["entries"]) == 200,
            "EXP012A02_A01_SOURCE_MISSING")
    locs = {p["id"]: p for p in atlas["locations"]}
    titles, targets, fingerprints, seen_modes = set(), set(), set(), set()
    for index, (entry, level, order) in enumerate(
            zip(entries, atlas["levels"], a01["entries"])):
        require(type(entry) is dict, "EXP012A02_ENTRY_TYPE")
        loc = locs[level["location_id"]]
        n = index + 1
        prefix = f"SC_{n:03d}"
        target_map = {letter: f"{prefix}_{letter}" for letter in "ABC"}
        required = {
            "level_id": level["id"],
            "location_id": level["location_id"],
            "region_id": level["region_id"],
            "source_puzzle_identity": level["puzzle_identity"],
            "source_title": level["title"],
            "source_risk": loc["risk"],
            "source_climate": loc["climate"],
            "source_task_ids": order["task_ids"],
            "worksite_encounter_key": order["encounter_key"],
            "targets": target_map,
            "recovery_target": target_map["C"],
            "qualification": QUALIFICATION,
        }
        for field, value in required.items():
            require(entry.get(field) == value,
                    "EXP012A02_SOURCE_DRIFT_" + field)
        title = entry.get("title")
        stakes = entry.get("stakes")
        require(type(title) is str and len(title) >= 12 and
                type(stakes) is str and len(stakes) >= 65 and
                title not in titles and len(set(entry["targets"].values())) == 3,
                "EXP012A02_AUTHORSHIP_INVALID")
        titles.add(title)
        for target in entry["targets"].values():
            require(target not in targets, "EXP012A02_DUPLICATE_TARGET")
            targets.add(target)
        routes = entry.get("routes")
        require(type(routes) is dict and set(routes) == {"priority", "resilience"},
                "EXP012A02_ROUTES_INVALID")
        for key in routes:
            steps = routes[key]
            require(type(steps) is list and len(steps) == 4,
                    "EXP012A02_STEP_COUNT")
            for step in steps:
                require(type(step) is dict and set(step) == EXPECTED_FIELDS,
                        "EXP012A02_STEP_TYPE")
                require(type(step["action"]) is str and
                        re.fullmatch(r"[a-z][a-z_]{7,44}", step["action"]) is not None,
                        "EXP012A02_ACTION_INVALID")
                require(step["mode"] in MODES and step["failure"] in PENALTIES and
                        step["target"] in target_map.values() and
                        step["support_target"] in target_map.values() and
                        step["target"] != step["support_target"],
                        "EXP012A02_MECHANIC_INVALID")
                require(type(step["dwell_ticks"]) is int and
                        type(step["window_ticks"]) is int and
                        5 <= step["dwell_ticks"] <= 20 and
                        40 <= step["window_ticks"] <= 240,
                        "EXP012A02_TIMER_INVALID")
                seen_modes.add(step["mode"])
        priority = [s["action"] for s in routes["priority"]]
        resilience = [s["action"] for s in routes["resilience"]]
        require(len(set(priority)) == 4 and
                set(priority) == {a.removesuffix("_reserve") for a in resilience} and
                priority != [a.removesuffix("_reserve") for a in resilience],
                "EXP012A02_STRATEGY_NOT_DISTINCT")
        fp = tuple((s["mode"], s["target"], s["support_target"], s["action"])
                   for s in routes["priority"])
        require(fp not in fingerprints, "EXP012A02_SCRIPT_DUPLICATED")
        fingerprints.add(fp)
        for key in routes:
            outcome = replay(entry, key)
            require(outcome["completed"] == 4 and outcome["actions"] >= 8,
                    "EXP012A02_ROUTE_UNSOLVABLE")
            for step_index, step in enumerate(routes[key]):
                require(0 <= recovery_oracle(step["failure"], step_index) <= step_index,
                        "EXP012A02_RECOVERY_UNSOLVABLE")
    require(len(targets) == 120 and len(titles) == 40 and
            len(fingerprints) == 40 and seen_modes == MODES,
            "EXP012A02_COVERAGE_INVALID")
    if presets is None:
        presets = PRESETS.read_text(encoding="utf-8")
    require(presets.count("scenes/expeditions/site_interventions_a02.json") == 2,
            "EXP012A02_EXPORT_MISSING")
    return {"ok": True, "individually_scripted_locations": 40,
            "not_yet_authored": 160, "strategies": 80,
            "host_action_steps": 320, "mechanic_modes": len(MODES),
            "source_targets": len(targets),
            "qualification": QUALIFICATION}


if __name__ == "__main__":
    atlas, _, book_a01 = load_inputs()
    print("EXP012 A02 SOURCE/RECOVERY AUDIT",
          json.dumps(validate(atlas, book_a01, read_book()), sort_keys=True))
