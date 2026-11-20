#!/usr/bin/env python3
"""EXP013 A04 independently verify all 200 authored intervention source bindings.

This is a *source catalog* gate, not a declaration of 200 separately finished
3D worksites, human/controller reach, balance, scene quality or production.
"""
from __future__ import annotations

import json

if __package__:
    from tools.validate_exp012_worksites import load_inputs
    from tools.validate_exp012_a02_sites import read_book as read_original_a02
    from tools.validate_exp012_a02_sites import validate as validate_original_a02
    from tools.validate_exp013_expansions import read_books, validate as validate_expansions
else:
    from validate_exp012_worksites import load_inputs
    from validate_exp012_a02_sites import read_book as read_original_a02
    from validate_exp012_a02_sites import validate as validate_original_a02
    from validate_exp013_expansions import read_books, validate as validate_expansions


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def validate(atlas: dict, a01: dict, original_a02: dict,
             exp013_books: list[dict]) -> dict:
    require(len(exp013_books) == 4, "EXP013_FINAL_MISSING_TRANCHE")
    validate_original_a02(atlas, a01, original_a02)
    exp_report = validate_expansions(atlas, a01, exp013_books)
    require(exp_report["total_individually_scripted"] == 200,
            "EXP013_FINAL_INCOMPLETE")
    entries = original_a02["entries"] + [
        entry for book in exp013_books for entry in book["entries"]]
    require(len(entries) == 200, "EXP013_FINAL_ENTRY_COUNT")
    levels = atlas["levels"]
    all_ids: set[str] = set()
    site_ids: set[str] = set()
    region_ids: set[str] = set()
    titles: set[str] = set()
    actions: set[str] = set()
    targets: set[str] = set()
    fingerprints: set[tuple] = set()
    routes = 0
    steps = 0
    for i, (entry, level) in enumerate(zip(entries, levels)):
        require(entry["level_id"] == level["id"], "EXP013_FINAL_LEVEL_ORDER")
        require(entry["level_id"] not in all_ids and
                entry["location_id"] not in site_ids, "EXP013_FINAL_DUPLICATED_LEVEL")
        all_ids.add(entry["level_id"])
        site_ids.add(entry["location_id"])
        region_ids.add(entry["region_id"])
        title = entry["title"]
        require(title not in titles, "EXP013_FINAL_REUSED_INTERVENTION_NAME")
        titles.add(title)
        expected_tasks = [task["id"] for task in level["tasks"]]
        require(entry["source_task_ids"] == expected_tasks and len(expected_tasks) == 5,
                "EXP013_FINAL_TASK_BINDING")
        for target in entry["targets"].values():
            require(target not in targets, "EXP013_FINAL_DUPLICATE_TARGET")
            targets.add(target)
        route_signatures = []
        for route in ("priority", "resilience"):
            route_data = entry["routes"][route]
            require(len(route_data) == 4, "EXP013_FINAL_INCOMPLETE_ROUTE")
            routes += 1
            steps += len(route_data)
            signature = tuple((s["action"], s["mode"], s["target"],
                               s["support_target"]) for s in route_data)
            route_signatures.append(signature)
            if route == "priority":
                for action in (step["action"] for step in route_data):
                    require(action not in actions, "EXP013_FINAL_DUPLICATE_ACTION")
                    actions.add(action)
        require(route_signatures[0] != route_signatures[1],
                "EXP013_FINAL_IDENTICAL_ROUTE")
        require(route_signatures[0] not in fingerprints,
                "EXP013_FINAL_DUPLICATE_INTERVENTION_GRAPH")
        fingerprints.add(route_signatures[0])
    require(len(all_ids) == len(site_ids) == len(titles) == 200,
            "EXP013_FINAL_COVERAGE")
    require(len(region_ids) == 25 and len(targets) == 600 and
            len(actions) == 800 and len(fingerprints) == 200 and
            routes == 400 and steps == 1600,
            "EXP013_FINAL_COMPLETENESS")
    task_ids = [task["id"] for level in levels for task in level["tasks"]]
    require(len(task_ids) == len(set(task_ids)) == 1000,
            "EXP013_FINAL_TASK_UNIQUENESS")
    return {
        "ok": True, "source_bound_locations": 200, "regions": 25,
        "original_mission_task_ids": 1000, "site_control_targets": 600,
        "distinct_priority_actions": 800, "distinct_primary_graphs": 200,
        "routes": 400, "steps": 1600,
        "source_qualification": "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD",
        "physical_playability_certified": False,
        "site_artwork_certified": False,
        "release_certified": False,
    }


if __name__ == "__main__":
    atlas, _, a01 = load_inputs()
    print("EXP013 FULL 200-SITE SOURCE CATALOG",
          json.dumps(validate(atlas, a01, read_original_a02(), read_books()),
                     sort_keys=True))
