#!/usr/bin/env python3
"""Independent source-authority audit for EXP013 A02/A03/A04.

The three extensions are independently authored forty-site overlays. Existing
A01 remains immutable. No generated script names, client-supplied tick clocks,
physical reach or Playability PASS is accepted by this source-level audit.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

if __package__:
    from tools.validate_exp012_worksites import load_inputs
    from tools.validate_exp013_sites import read_book as read_a01, validate as validate_a01
    from tools.validate_exp012_a02_sites import replay, recovery_oracle
else:
    from validate_exp012_worksites import load_inputs
    from validate_exp013_sites import read_book as read_a01, validate as validate_a01
    from validate_exp012_a02_sites import replay, recovery_oracle

ROOT = Path(__file__).resolve().parents[1]
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
SOURCES = {
    81: ROOT / "scenes/expeditions/site_interventions_exp013_a02.json",
    121: ROOT / "scenes/expeditions/site_interventions_exp013_a03.json",
    161: ROOT / "scenes/expeditions/site_interventions_exp013_a04.json",
}
MODES = {"hold", "pulse", "sample", "handoff", "balance"}
FAILURES = {"step", "backtrack", "restart"}
FIELDS = {"action", "mode", "target", "support_target", "dwell_ticks",
          "window_ticks", "failure"}


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def read_books() -> list[dict]:
    books = [read_a01()]
    found_gap = False
    for path in SOURCES.values():
        if not path.is_file():
            found_gap = True
            continue
        require(not found_gap, "EXP013_NONCONTIGUOUS_BOOKS")
        books.append(json.loads(path.read_text(encoding="utf-8")))
    return books


def validate(atlas: dict, orders: dict, books: list[dict],
             presets: str | None = None) -> dict:
    if presets is None:
        presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    require(type(books) is list and 2 <= len(books) <= 4,
            "EXP013_EXTENSION_COUNT_INVALID")
    # A01 and earlier authoritative identifiers must remain source-valid.
    validate_a01(atlas, orders, books[0], presets)
    location_ids: set[str] = set()
    source_targets: set[str] = set()
    titles: set[str] = set()
    action_ids: set[str] = set()
    placements: set[tuple] = set()
    for book_index, book in enumerate(books):
        start = 41 + 40 * book_index
        expected_authority = f"EXP013_A0{book_index + 1}_HOST_SITE_INTERVENTIONS"
        require(book.get("schema_version") == 1 and
                book.get("atlas_revision") == atlas["revision"] and
                book.get("authority") == expected_authority and
                book.get("qualification") == QUALIFICATION,
                "EXP013_EXTENSION_HEADER_INVALID")
        entries = book.get("entries")
        require(type(entries) is list and len(entries) == 40,
                "EXP013_EXTENSION_CASE_COUNT_INVALID")
        for index, entry in enumerate(entries):
            n = start + index
            level, order = atlas["levels"][n - 1], orders["entries"][n - 1]
            location = next(loc for loc in atlas["locations"]
                            if loc["id"] == level["location_id"])
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
            for key, value in expected.items():
                require(entry.get(key) == value,
                        "EXP013_EXTENSION_SOURCE_DRIFT_" + key)
            require(level["id"] not in location_ids, "EXP013_EXTENSION_DUPLICATE_SITE")
            location_ids.add(level["id"])
            title, stakes = entry.get("title"), entry.get("stakes")
            require(type(title) is str and len(title) >= 12 and
                    type(stakes) is str and len(stakes) >= 65 and
                    title not in titles, "EXP013_EXTENSION_AUTHORSHIP_INVALID")
            titles.add(title)
            expected_targets = {c: f"SC_{n:03d}_{c}" for c in "ABC"}
            require(entry.get("targets") == expected_targets and
                    entry.get("recovery_target") == expected_targets["C"],
                    "EXP013_EXTENSION_TARGET_DRIFT")
            for target in expected_targets.values():
                require(target not in source_targets, "EXP013_EXTENSION_DUPLICATE_TARGET")
                source_targets.add(target)
            offsets = entry.get("station_offsets_cm")
            require(type(offsets) is dict and set(offsets) == set("ABC"),
                    "EXP013_EXTENSION_STATIONS_INVALID")
            for pair in offsets.values():
                require(type(pair) is list and len(pair) == 2 and
                        all(type(v) is int for v in pair) and
                        -300 <= pair[0] <= 300 and 70 <= pair[1] <= 300,
                        "EXP013_EXTENSION_STATIONS_INVALID")
            placement = tuple(tuple(offsets[c]) for c in "ABC")
            require(placement not in placements, "EXP013_EXTENSION_DUPLICATE_PLACEMENT")
            placements.add(placement)
            routes = entry.get("routes")
            require(type(routes) is dict and set(routes) == {"priority", "resilience"},
                    "EXP013_EXTENSION_ROUTES_INVALID")
            sequences: dict[str, list[str]] = {}
            for route in ("priority", "resilience"):
                steps = routes[route]
                require(type(steps) is list and len(steps) == 4,
                        "EXP013_EXTENSION_STEPS_INVALID")
                for step in steps:
                    require(type(step) is dict and set(step) == FIELDS,
                            "EXP013_EXTENSION_STEP_SHAPE_INVALID")
                    require(type(step["action"]) is str and re.fullmatch(
                        r"[a-z][a-z_]{7,44}", step["action"]) is not None,
                        "EXP013_EXTENSION_ACTION_INVALID")
                    require(step["mode"] in MODES and step["failure"] in FAILURES and
                            step["target"] in expected_targets.values() and
                            step["support_target"] in expected_targets.values() and
                            step["target"] != step["support_target"],
                            "EXP013_EXTENSION_MECHANIC_INVALID")
                    require(type(step["dwell_ticks"]) is int and
                            type(step["window_ticks"]) is int and
                            5 <= step["dwell_ticks"] <= 20 and
                            40 <= step["window_ticks"] <= 240,
                            "EXP013_EXTENSION_TIMER_INVALID")
                    if route == "priority":
                        require(step["action"] not in action_ids,
                                "EXP013_EXTENSION_DUPLICATE_ACTION")
                        action_ids.add(step["action"])
                require(replay(entry, route)["completed"] == 4,
                        "EXP013_EXTENSION_DEADLOCK")
                for i, step in enumerate(steps):
                    require(0 <= recovery_oracle(step["failure"], i) <= i,
                            "EXP013_EXTENSION_RECOVERY_UNSAFE")
                sequences[route] = [s["action"] if route == "priority" else
                                    s["action"].removesuffix("_reserve") for s in steps]
            require(len(set(sequences["priority"])) == 4 and
                    set(sequences["priority"]) == set(sequences["resilience"]) and
                    sequences["priority"] != sequences["resilience"],
                    "EXP013_EXTENSION_COSMETIC_STRATEGY")
        source_name = (
            "scenes/expeditions/site_interventions_exp013.json"
            if book_index == 0 else
            f"scenes/expeditions/site_interventions_exp013_a0{book_index + 1}.json"
        )
        require(presets.count(source_name) == 2, "EXP013_EXTENSION_EXPORT_MISSING")
    expected_count = 40 * len(books)
    require(len(location_ids) == len(source_targets) // 3 == len(titles) ==
            len(placements) == expected_count and
            len(action_ids) == expected_count * 4,
            "EXP013_EXTENSION_COVERAGE_INVALID")
    return {
        "ok": True, "exp013_sources": len(books),
        "total_individually_scripted": 40 + expected_count,
        "exp013_authored_sites": expected_count,
        "remaining_uncovered": 200 - 40 - expected_count,
        "additional_routes": (len(books) - 1) * 80,
        "additional_steps": (len(books) - 1) * 320,
        "additional_targets": (len(books) - 1) * 120,
        "distinct_action_ids": len(action_ids),
        "qualification": QUALIFICATION,
    }


if __name__ == "__main__":
    atlas, _, a01 = load_inputs()
    print("EXP013 A02-A04 INDEPENDENT COLLECTION AUDIT",
          json.dumps(validate(atlas, a01, read_books()), sort_keys=True))
