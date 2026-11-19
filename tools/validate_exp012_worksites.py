#!/usr/bin/env python3
"""EXP012 independent, read-only audit of source-pinned worksite encounter graphs.

Authoring source is data, not client claims or inferred task completion. Validate
all legacy atlas task IDs, EXP011 service links, two distinct DAGs per worksite,
safe slow completion paths, finite rapid consumables, and export membership.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "scenes/expeditions/atlas.json"
LOADS = ROOT / "scenes/expeditions/critical_service_loads.json"
BOOK = ROOT / "scenes/expeditions/field_work_orders.json"
PRESETS = ROOT / "export_presets.cfg"
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
AUTHORITY = "EXP012_HOST_FIELD_WORK_ORDERS"
SITES = ("distribution", "transport", "health", "commerce",
         "waterworks", "communications", "education", "shelter")
GRAPHS = {
    "distribution": {"priority": ((), (), (0, 1)), "resilience": ((), (0,), (1,))},
    "transport": {"priority": ((), (), (0, 1)), "resilience": ((1,), (), (0,))},
    "health": {"priority": ((1,), (), (0, 1)), "resilience": ((), (0,), (1,))},
    "commerce": {"priority": ((), (0,), (0,)), "resilience": ((1,), (), (0, 1))},
    "waterworks": {"priority": ((), (0,), (1,)), "resilience": ((), (), (0, 1))},
    "communications": {"priority": ((), (), (0,)), "resilience": ((2,), (0,), ())},
    "education": {"priority": ((), (), (0, 1)), "resilience": ((2,), (2,), ())},
    "shelter": {"priority": ((), (0,), (0, 1)), "resilience": ((1,), (), (0, 1))},
}


def load_inputs() -> tuple[dict, dict, dict]:
    return tuple(json.loads(path.read_text(encoding="utf-8"))
                 for path in (ATLAS, LOADS, BOOK))


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise ValueError(reason)


def route_replay(entry: dict, route: str, rapid: bool = False) -> dict:
    """Run an independent host-tick model; all routes must remain completable.

    Rapid consumes one calibration cell at the start; exhausted cells must
    always leave a nonconsumable precision alternative. No client clock used.
    """
    checkpoints = entry["checkpoints"]
    pending = {step["id"]: step for step in checkpoints}
    completed: set[str] = set()
    cells = entry["cell_budget"]
    ticks = 0
    order: list[str] = []
    deps = {step["id"]: set(entry["routes"][route][i])
            for i, step in enumerate(checkpoints)}
    while pending:
        ready = [step for step in checkpoints
                 if step["id"] in pending and deps[step["id"]] <= completed]
        require(bool(ready), "EXP012_CYCLIC_OR_DEADLOCKED")
        step = ready[0]
        do_rapid = rapid and cells > 0
        if do_rapid:
            cells -= 1
        ticks += step["rapid_ticks"] if do_rapid else step["precision_ticks"]
        completed.add(step["id"])
        order.append(step["id"])
        del pending[step["id"]]
    require(len(order) == 3 and cells >= 0, "EXP012_REFERENCE_INVALID")
    return {"route": route, "order": order, "ticks": ticks, "cells_left": cells}


def validate(atlas: dict, loads: dict, book: dict, presets: str | None = None) -> dict:
    require(book.get("schema_version") == 1
            and book.get("authority") == AUTHORITY
            and book.get("atlas_revision") == atlas.get("revision")
            and book.get("qualification") == QUALIFICATION
            and book.get("profiles") == list(SITES), "EXP012_HEADER_INVALID")
    entries = book.get("entries")
    require(type(entries) is list and len(entries) == 200, "EXP012_COUNT_INVALID")
    levels = atlas.get("levels", [])
    locations = {l["id"]: l for l in atlas["locations"]}
    source_loads = {e["level_id"]: e for e in loads["entries"]}
    require(len(levels) == 200 and len(locations) == 200
            and len(source_loads) == 200, "EXP012_SOURCE_COUNTS_INVALID")
    unique_targets: set[str] = set()
    unique_keys: set[str] = set()
    regions: set[str] = set()
    site_pairs: set[tuple[str, str]] = set()
    for index, (level, entry) in enumerate(zip(levels, entries)):
        require(type(entry) is dict, "EXP012_ENTRY_NOT_OBJECT")
        location = locations[level["location_id"]]
        linked = source_loads[level["id"]]
        region = int(level["region_id"].removeprefix("REG_"))
        site = location["archetype"]
        suffix = level["id"].removeprefix("LV_")
        checkpoints = entry.get("checkpoints", [])
        ids = [f"WO_{suffix}_{s}" for s in "ABC"]
        required = {
            "level_id": level["id"], "location_id": level["location_id"],
            "region_id": level["region_id"],
            "source_puzzle_identity": level["puzzle_identity"],
            "site": site, "source_climate": location["climate"],
            "load_key": linked["load_key"],
            "encounter_key": f'{linked["load_key"]}|EXP012|{site}|{region}',
            "task_ids": [task["id"] for task in level["tasks"]],
            "board": f"WO_{suffix}_BOARD",
            "decision": f"WO_{suffix}_ROUTE",
            "console": f"WO_{suffix}_CTRL",
            "optional_target": f"WO_{suffix}_DISC",
            "anchors": {
                "board": "PANEL_WEST", "decision": "PANEL_SPUR",
                "console": "R_WEST", "optional_target": "PANEL_SPUR",
            },
            "cell_budget": 1 + region % 3,
            "crew_capacity": 1 + region % 2,
            "source_title": level["title"],
            "qualification": QUALIFICATION,
        }
        require(type(entry.get("cell_budget")) is int
                and type(entry.get("crew_capacity")) is int,
                "EXP012_RESOURCE_TYPE_INVALID")
        for key, expected in required.items():
            require(entry.get(key) == expected, "EXP012_SOURCE_DRIFT_" + key)
        require(isinstance(checkpoints, list) and len(checkpoints) == 3,
                "EXP012_CHECKPOINTS_INVALID")
        expected_routes = {
            route: [[ids[n] for n in dep] for dep in pattern]
            for route, pattern in GRAPHS[site].items()
        }
        require(entry.get("routes") == expected_routes
                and entry["routes"]["priority"] != entry["routes"]["resilience"],
                "EXP012_ROUTES_INVALID")
        for offset, step in enumerate(checkpoints):
            source = linked["services"][offset]
            expected = {
                "id": ids[offset],
                "anchor": ("PANEL_WEST", "PANEL_SPUR", "R_WEST")[offset],
                "linked_service": source["id"],
                "source_task_id": level["tasks"][offset]["id"],
                "title": source["name"],
                "precision_ticks": 6 + (source["dwell_ticks"] + region + offset) % 7,
                "rapid_ticks": 2 + (index + offset) % 3,
            }
            require(step == expected, "EXP012_CHECKPOINT_DRIFT")
        targets = [required[key] for key in
                   ("board", "decision", "console", "optional_target")] + ids
        require(not unique_targets.intersection(targets),
                "EXP012_DUPLICATE_TARGET")
        unique_targets.update(targets)
        require(entry["encounter_key"] not in unique_keys,
                "EXP012_DUPLICATE_ENCOUNTER")
        unique_keys.add(entry["encounter_key"])
        regions.add(level["region_id"])
        site_pairs.add((level["region_id"], site))
        for route in ("priority", "resilience"):
            route_replay(entry, route, rapid=False)
            route_replay(entry, route, rapid=True)
    require(len(unique_targets) == 1400 and len(unique_keys) == 200
            and len(regions) == 25 and len(site_pairs) == 200,
            "EXP012_COVERAGE_INVALID")
    if presets is None:
        presets = PRESETS.read_text(encoding="utf-8")
    require(presets.count("scenes/expeditions/field_work_orders.json") == 2,
            "EXP012_WINDOWS_EXPORT_MISSING")
    return {"ok": True, "levels": len(entries), "task_bindings": 1000,
            "checkpoints": 600, "targets": len(unique_targets),
            "regions": len(regions), "site_families": len(SITES),
            "alternative_routes": len(entries) * 2}


if __name__ == "__main__":
    atlas, loads, book = load_inputs()
    print("EXP012 SOURCE AUDIT",
          json.dumps(validate(atlas, loads, book), sort_keys=True))
