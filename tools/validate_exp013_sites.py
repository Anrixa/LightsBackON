#!/usr/bin/env python3
"""EXP013 A01 independent LV_041–LV_080 source/route audit.

Validates the additional hand-authored interventions against the immutable EXP01
atlas and EXP012 A01 source identities; does not certify physical playability.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

if __package__:
    from tools.validate_exp012_worksites import load_inputs
    from tools.validate_exp012_a02_sites import replay, recovery_oracle
else:
    from validate_exp012_worksites import load_inputs
    from validate_exp012_a02_sites import replay, recovery_oracle

ROOT = Path(__file__).resolve().parents[1]
BOOK = ROOT / "scenes/expeditions/site_interventions_exp013.json"
PRESETS = ROOT / "export_presets.cfg"
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
MODES = {"hold", "pulse", "sample", "handoff", "balance"}
FAILURES = {"step", "backtrack", "restart"}
STEP_FIELDS = {"action", "mode", "target", "support_target", "dwell_ticks", "window_ticks", "failure"}


def require(ok: bool, code: str) -> None:
    if not ok:
        raise ValueError(code)


def read_book() -> dict:
    return json.loads(BOOK.read_text(encoding="utf-8"))


def validate(atlas: dict, a01: dict, book: dict, presets: str | None = None) -> dict:
    require(book.get("schema_version") == 1 and
            book.get("authority") == "EXP013_A01_HOST_SITE_INTERVENTIONS" and
            book.get("atlas_revision") == atlas.get("revision") and
            book.get("qualification") == QUALIFICATION, "EXP013_HEADER_INVALID")
    entries = book.get("entries")
    require(type(entries) is list and len(entries) == 40 and
            len(atlas["levels"]) == 200 and len(a01["entries"]) == 200,
            "EXP013_COUNT_INVALID")
    locations = {loc["id"]: loc for loc in atlas["locations"]}
    titles, signatures, targets, placements, modes = set(), set(), set(), set(), set()
    for offset, entry in enumerate(entries):
        require(type(entry) is dict, "EXP013_ENTRY_INVALID")
        serial = offset + 41
        level = atlas["levels"][serial - 1]
        order = a01["entries"][serial - 1]
        location = locations[level["location_id"]]
        expected = {
            "level_id": level["id"],
            "location_id": level["location_id"],
            "region_id": level["region_id"],
            "source_puzzle_identity": level["puzzle_identity"],
            "source_title": level["title"],
            "source_risk": location["risk"],
            "source_climate": location["climate"],
            "source_task_ids": order["task_ids"],
            "worksite_encounter_key": order["encounter_key"],
            "qualification": QUALIFICATION,
        }
        for field, value in expected.items():
            require(entry.get(field) == value, "EXP013_SOURCE_DRIFT_" + field)
        require(type(entry.get("title")) is str and
                len(entry["title"]) >= 12 and entry["title"] not in titles and
                type(entry.get("stakes")) is str and len(entry["stakes"]) >= 65,
                "EXP013_AUTHORSHIP_INVALID")
        titles.add(entry["title"])
        prefix = f"SC_{serial:03d}"
        expected_targets = {k: f"{prefix}_{k}" for k in "ABC"}
        require(entry.get("targets") == expected_targets and
                entry.get("recovery_target") == expected_targets["C"],
                "EXP013_TARGET_INVALID")
        for target in expected_targets.values():
            require(target not in targets, "EXP013_DUPLICATE_TARGET")
            targets.add(target)
        stations = entry.get("station_offsets_cm")
        require(type(stations) is dict and set(stations) == set("ABC"),
                "EXP013_POSITION_INVALID")
        for pair in stations.values():
            require(type(pair) is list and len(pair) == 2 and
                    all(type(value) is int for value in pair) and
                    -300 <= pair[0] <= 300 and 70 <= pair[1] <= 300,
                    "EXP013_POSITION_INVALID")
        placement = tuple(tuple(stations[k]) for k in "ABC")
        require(placement not in placements, "EXP013_REUSED_STATION_PLAN")
        placements.add(placement)
        routes = entry.get("routes")
        require(type(routes) is dict and set(routes) == {"priority", "resilience"},
                "EXP013_ROUTE_INVALID")
        route_actions = {}
        for route in ("priority", "resilience"):
            steps = routes[route]
            require(type(steps) is list and len(steps) == 4, "EXP013_STEP_COUNT")
            for step in steps:
                require(type(step) is dict and set(step) == STEP_FIELDS,
                        "EXP013_STEP_INVALID")
                require(type(step["action"]) is str and
                        re.fullmatch(r"[a-z][a-z_]{7,44}", step["action"]) is not None,
                        "EXP013_ACTION_INVALID")
                require(step["mode"] in MODES and step["failure"] in FAILURES and
                        step["target"] in expected_targets.values() and
                        step["support_target"] in expected_targets.values() and
                        step["target"] != step["support_target"],
                        "EXP013_STEP_INVALID")
                require(type(step["dwell_ticks"]) is int and
                        type(step["window_ticks"]) is int and
                        5 <= step["dwell_ticks"] <= 20 and
                        40 <= step["window_ticks"] <= 240,
                        "EXP013_TIMER_INVALID")
                modes.add(step["mode"])
            require(replay(entry, route)["completed"] == 4, "EXP013_REPLAY_FAILED")
            for i, step in enumerate(steps):
                require(0 <= recovery_oracle(step["failure"], i) <= i,
                        "EXP013_RECOVERY_UNSOLVABLE")
            route_actions[route] = [s["action"] for s in steps]
        priority = route_actions["priority"]
        resilience = [action.removesuffix("_reserve") for action
                      in route_actions["resilience"]]
        require(len(set(priority)) == 4 and set(priority) == set(resilience) and
                priority != resilience, "EXP013_STRATEGY_NOT_DISTINCT")
        signature = tuple((s["action"], s["mode"], s["target"], s["support_target"])
                          for s in routes["priority"])
        require(signature not in signatures, "EXP013_DUPLICATE_SCRIPT")
        signatures.add(signature)
    require(len(targets) == 120 and len(titles) == 40 and
            len(placements) == 40 and len(signatures) == 40 and modes == MODES,
            "EXP013_COVERAGE_INVALID")
    if presets is None:
        presets = PRESETS.read_text(encoding="utf-8")
    require(presets.count("scenes/expeditions/site_interventions_exp013.json") == 2,
            "EXP013_EXPORT_MISSING")
    return {"ok": True, "new_individually_scripted": 40,
            "cumulative_individually_scripted": 80, "remaining": 120,
            "new_routes": 80, "new_steps": 320, "new_targets": 120,
            "mechanical_modes": len(modes), "qualification": QUALIFICATION}


if __name__ == "__main__":
    atlas, _, a01 = load_inputs()
    print("EXP013 A01 SOURCE/RECOVERY AUDIT",
          json.dumps(validate(atlas, a01, read_book()), sort_keys=True))
