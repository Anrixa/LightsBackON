#!/usr/bin/env python3
"""Independent EXP01 content contract validator (headless; no gameplay claims)."""
from __future__ import annotations

import collections
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "scenes/expeditions/atlas.json"
SEEDS = ROOT / "docs/design/EXP01-atlas-seeds.json"
KINDS = (
    "investigation", "power_routing", "field_repair",
    "optional_discovery", "restoration",
)


def audit(data: dict[str, Any], seeds: dict[str, Any] | None = None) -> dict[str, int]:
    def ensure(condition: bool, message: str) -> None:
        if not condition:
            raise ValueError(message)

    ensure(data.get("schema_version") == 1, "unsupported atlas schema")
    ensure(data.get("authority") == "DESIGN_PREVIEW_ONLY_NOT_GAMEPLAY", "atlas must not grant host authority")
    ensure(data.get("legacy_campaign_contracts_unchanged") is True, "legacy authority guard missing")
    regions = data.get("regions")
    locations = data.get("locations")
    levels = data.get("levels")
    ensure(isinstance(regions, list) and len(regions) == 25, "exactly 25 regions required")
    ensure(isinstance(locations, list) and len(locations) == 200, "exactly 200 locations required")
    ensure(isinstance(levels, list) and len(levels) == 200, "exactly 200 levels required")
    ensure(len({r["id"] for r in regions}) == 25, "duplicate region ID")
    names = [location["name"] for location in locations]
    ensure(len(set(names)) == 200 and all(names), "location names must all be unique")
    ids = [location["id"] for location in locations]
    ensure(len(set(ids)) == 200, "duplicate location IDs")
    region_ids = {r["id"] for r in regions}
    by_region = collections.Counter(location["district_id"] for location in locations)
    ensure(set(by_region) == region_ids and all(n == 8 for n in by_region.values()), "eight locations per region")
    ensure(all(l["production_status"] == "UNBUILT_LOCATION" for l in locations), "false physical certification")
    ensure(all(isinstance(l["planning_anchor_cm"], list) and len(l["planning_anchor_cm"]) == 2 for l in locations),
           "invalid candidate planning coordinates")
    loc_region = {location["id"]: location["district_id"] for location in locations}
    ensure(len({level["id"] for level in levels}) == 200, "duplicate level ID")
    ensure({level["location_id"] for level in levels} == set(ids), "location/level coverage mismatch")
    task_ids: list[str] = []
    task_briefs: list[str] = []
    mechanics: set[str] = set()
    puzzle_keys: set[str] = set()
    collectible_ids: set[str] = set()
    for level in levels:
        lid = level["id"]
        ensure(level["region_id"] == loc_region[level["location_id"]], f"{lid}: wrong region")
        ensure(level["runtime_status"] == "DESIGN_BRIEFING_ONLY", f"{lid}: level not host-enabled")
        ensure(level["scoring_authority"] == "PREVIEW_POINTS_ONLY", f"{lid}: preview must not award currency")
        ensure(level.get("original_campaign_id") is None, f"{lid}: original campaign reference prohibited")
        ensure(len(level["mission_hook"]) >= 60, f"{lid}: missing story hook")
        puzzle_keys.add(level["puzzle_identity"])
        tasks = level.get("tasks")
        ensure(isinstance(tasks, list) and len(tasks) == 5, f"{lid}: need 5 tasks")
        for k, task in enumerate(tasks):
            tid = task["id"]
            ensure(task["ordinal"] == k + 1 and task["kind"] == KINDS[k], f"{tid}: wrong stage")
            ensure(task["required"] is (k != 3), f"{tid}: optional task improperly gates completion")
            ensure(task["status"] == "DESIGN_ONLY_NOT_HOST_ENABLED", f"{tid}: unqualified authority")
            ensure(isinstance(task["field_points_preview"], int) and
                   0 <= task["field_points_preview"] <= 200, f"{tid}: invalid preview points")
            ensure(isinstance(task["timing_hint_ticks"], int) and
                   task["timing_hint_ticks"] >= 0, f"{tid}: invalid duration")
            ensure(len(task["briefing"]) >= 75 and len(task["title"]) >= 18,
                   f"{tid}: missing objective writing")
            task_ids.append(tid)
            task_briefs.append(task["briefing"])
            mechanics.add(task["mechanic"])
        collectible = level["collectible"]
        collectible_ids.add(collectible["id"])
        ensure(collectible["discovery_task_id"] == tasks[3]["id"], f"{lid}: collectible not optional")
        ensure(collectible["status"] == "PLANNED_NOT_COLLECTIBLE", f"{lid}: false pickup claim")
        ensure(collectible["effect"] == "LORE_ONLY_NO_POWER_OR_CREDITS", f"{lid}: forbidden gameplay reward")
    ensure(len(task_ids) == 1000 and len(set(task_ids)) == 1000, "need 1000 unique task IDs")
    ensure(len(set(task_briefs)) == 1000, "duplicate task briefings")
    ensure(len(puzzle_keys) == 200, "repeated level puzzle signature")
    ensure(len(collectible_ids) == 200, "duplicate collectible ID")
    ensure(len(mechanics) >= 20, "insufficient task mechanic variety")
    ensure(data["scope"] == {
        "regions": 25, "locations": 200, "levels": 200,
        "tasks": 1000, "collectibles": 200,
    }, "untruthful scope totals")
    if seeds is not None:
        ensure(len(seeds["regions"]) == 25, "seed region count mismatch")
        for r, candidate in zip(seeds["regions"], regions):
            ensure(r["id"] == candidate["id"], "seed region order changed")
            expected = {loc["name"] for loc in locations if loc["district_id"] == r["id"]}
            ensure(set(r["sites"]) == expected and len(expected) == 8, f"{r['id']}: seed site drift")
    return {
        "regions": len(regions), "locations": len(locations), "levels": len(levels),
        "tasks": len(task_ids), "collectibles": len(collectible_ids),
        "mechanics": len(mechanics), "unique_puzzle_signatures": len(puzzle_keys),
    }


def main() -> int:
    try:
        print(f"EXP01_STAGE=LOAD source={ATLAS} seeds={SEEDS}", flush=True)
        data = json.loads(ATLAS.read_text(encoding="utf-8"))
        seeds = json.loads(SEEDS.read_text(encoding="utf-8"))
        report = audit(data, seeds)
    except (ValueError, KeyError, TypeError, OSError, json.JSONDecodeError) as error:
        print(f"EXP01_GATE=FAIL reason={error}", file=sys.stderr, flush=True)
        return 1
    print("EXP01_GATE=PASS " + " ".join(f"{k}={v}" for k, v in report.items()), flush=True)
    print("EXP01_CEILING=DESIGN_BRIEFINGS_ONLY_NO_HOST_COMMANDS_NO_PHYSICAL_PLAYABILITY",
          flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
