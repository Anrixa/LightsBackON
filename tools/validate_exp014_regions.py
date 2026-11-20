#!/usr/bin/env python3
"""EXP014 A03 independent source/geometry-envelope audit.

This checks the 25 hand-authored Godot facility recipes against the immutable
atlas and replays all 200 deterministic slot/stand-off calculations in Python.
Axis-aligned 2D separations are static design evidence, NOT collision/navmesh,
camera, reachability, controller, hardware or release certification.
"""
from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/world/expedition_regional_facilities.gd"
ATLAS = ROOT / "scenes/expeditions/atlas.json"
RECIPE = re.compile(
    r'^\s*"(REG_\d{2})": \{"risk":"([^"]+)", "forms":\[([^]]+)\], '
    r'"cue":"([^"]+)", "tone":"(#[A-Fa-f0-9]{6})"\},?$',
    re.MULTILINE,
)
FORM = re.compile(r'"([^"]+)"')
CATEGORIES = (
    "distribution", "transport", "health", "commerce", "waterworks",
    "communications", "education", "shelter",
)
KNOWN_FORMS = {
    "arch", "channel", "cabinet", "gantry", "silo", "rack", "screen", "mast",
    "truss", "bridge", "pylon", "cistern", "shed", "stair", "baffle", "hoist",
    "stack", "vent", "gate", "canopy", "tower",
}
HALF = 4.4
STANDOFF = 2.4
PROTECTED = (
    ((7.5, 40), (8, 5.6)),
    ((43, 9), (3.7, 4.2)),
    ((41.5, 40.5), (4, 3.9)),
)
CELLS = tuple((float(x), float(z)) for z in (7, 17, 27, 37, 47)
              for x in (7, 17, 27, 37, 47))


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def read_recipes(source: str | None = None) -> dict[str, dict]:
    source = SCRIPT.read_text(encoding="utf-8") if source is None else source
    recipes: dict[str, dict] = {}
    for match in RECIPE.finditer(source):
        region, risk, form_string, cue, tone = match.groups()
        require(region not in recipes, "EXP014_A03_DUPLICATE_RECIPE")
        recipes[region] = {
            "risk": risk, "forms": FORM.findall(form_string),
            "cue": cue, "tone": tone,
        }
    require(len(recipes) == 25, "EXP014_A03_RECIPE_COUNT")
    return recipes


def positions(serial: int, category: str) -> list[tuple[float, float]]:
    """Independent EXP02 planning formula; no reliance on render metadata."""
    turn = (serial + CATEGORIES.index(category)) % 4
    result = []
    for k in range(5):
        x_cm = (880 + k * 800 + (((serial * 37 + k * 19) % 5) - 2) * 40
                + ((serial * 73) % 200) - 100)
        z_cm = (1150 + k * 690 + (((serial * 11 + k * 29) % 7) - 3) * 50
                + ((serial * 97) % 180) - 90)
        if turn == 0:
            x, z = x_cm, z_cm
        elif turn == 1:
            x, z = z_cm, 5200 - x_cm
        elif turn == 2:
            x, z = 5200 - x_cm, 5200 - z_cm
        else:
            x, z = 5200 - z_cm, x_cm
        result.append((x / 100, z / 100))
    return result


def overlaps(a: tuple[float, float], b: tuple[float, float],
             half_a: tuple[float, float],
             half_b: tuple[float, float]) -> bool:
    return (abs(a[0] - b[0]) < half_a[0] + half_b[0]
            and abs(a[1] - b[1]) < half_a[1] + half_b[1])


def clearance(anchor: tuple[float, float],
              stations: list[tuple[float, float]]) -> float:
    return min(
        (max(abs(anchor[0] - x) - HALF, 0.0) ** 2 +
         max(abs(anchor[1] - z) - HALF, 0.0) ** 2) ** 0.5
        for x, z in stations
    )


def slot_clear(anchor: tuple[float, float],
               stations: list[tuple[float, float]]) -> bool:
    x, z = anchor
    if min(x, z) - HALF < 0 or max(x, z) + HALF > 52:
        return False
    if any(overlaps(anchor, point, (HALF, HALF), extent)
           for point, extent in PROTECTED):
        return False
    return clearance(anchor, stations) >= STANDOFF


def choose(serial: int, region_number: int,
           stations: list[tuple[float, float]]) -> tuple[int, tuple[float, float]]:
    first = (serial * 7 + region_number * 3) % len(CELLS)
    for step in range(len(CELLS)):
        slot = (first + step) % len(CELLS)
        if slot_clear(CELLS[slot], stations):
            return slot, CELLS[slot]
    raise ValueError(f"EXP014_A03_NO_FREE_FACILITY_SLOT_{serial:03d}")


def validate(atlas: dict, recipes: dict[str, dict]) -> dict:
    regions, locations, levels = (atlas[key] for key in
                                  ("regions", "locations", "levels"))
    require((len(regions), len(locations), len(levels)) == (25, 200, 200),
            "EXP014_A03_ATLAS_SIZE")
    require(set(recipes) == {f"REG_{i:02d}" for i in range(1, 26)},
            "EXP014_A03_REGION_MAP")
    structural: set[tuple] = set()
    cues: set[str] = set()
    for number, region in enumerate(regions, 1):
        region_id = f"REG_{number:02d}"
        require(region["id"] == region_id, "EXP014_A03_REGION_SEQUENCE")
        recipe = recipes[region_id]
        require(region["hazard"] == recipe["risk"], "EXP014_A03_RISK_DRIFT")
        forms = recipe["forms"]
        require(len(forms) == 4 and len(set(forms)) == 4
                and set(forms) <= KNOWN_FORMS, "EXP014_A03_INVALID_FORMS")
        require(recipe["cue"] not in cues, "EXP014_A03_REUSED_ENCOUNTER")
        cues.add(recipe["cue"])
        structural.add((tuple(forms), recipe["cue"]))
    require(len(structural) == 25, "EXP014_A03_REUSED_GEOMETRY")
    require(len({tuple(recipes[k]["forms"]) for k in recipes}) == 25,
            "EXP014_A03_COSMETIC_ONLY_VARIETY")
    identifiers: set[str] = set()
    task_ids: set[str] = set()
    slots: Counter[int] = Counter()
    min_clearance = 1000.0
    for serial, (location, level) in enumerate(zip(locations, levels), 1):
        identity = f"LV_{serial:03d}"
        region_number = (serial - 1) // 8 + 1
        region_id = f"REG_{region_number:02d}"
        require((level["id"], level["location_id"], level["region_id"]) ==
                (identity, f"LOC_{serial:03d}", region_id),
                "EXP014_A03_SITE_IDENTITY")
        require((location["id"], location["district_id"], location["risk"]) ==
                (f"LOC_{serial:03d}", region_id, recipes[region_id]["risk"]),
                "EXP014_A03_LOCATION_RISK_DRIFT")
        require(location["archetype"] in CATEGORIES,
                "EXP014_A03_SITE_ARCHETYPE")
        require(len(level["tasks"]) == 5, "EXP014_A03_TASK_COUNT")
        for k, task in enumerate(level["tasks"], 1):
            expected = f"JOB_{serial:03d}_{k}"
            require(task["id"] == expected and expected not in task_ids,
                    "EXP014_A03_TASK_DRIFT")
            task_ids.add(expected)
        station_points = positions(serial, location["archetype"])
        slot, anchor = choose(serial, region_number, station_points)
        slots[slot] += 1
        min_clearance = min(min_clearance, clearance(anchor, station_points))
        require(all(not overlaps(anchor, point, (HALF, HALF), extent)
                    for point, extent in PROTECTED),
                "EXP014_A03_FACILITY_LANDMARK_INTERSECTION")
        identifiers.add(identity)
    require(len(identifiers) == 200 and len(task_ids) == 1000,
            "EXP014_A03_SOURCE_COVERAGE")
    require(min_clearance >= STANDOFF, "EXP014_A03_STATION_STANDOFF")
    return {
        "ok": True, "regional_geometry_packages": len(structural),
        "noncosmetic_facility_silhouettes": len(
            {tuple(recipes[k]["forms"]) for k in recipes}),
        "distinct_environmental_cues": len(cues),
        "audited_source_levels": len(identifiers),
        "preserved_source_tasks": len(task_ids),
        "selected_nonoverlapping_facility_slots": len(slots),
        "minimum_static_station_standoff_m": round(min_clearance, 3),
        "collision_or_reachability_certified": False,
        "human_controller_or_hardware_certified": False,
        "release_certified": False,
        "qualification": "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD",
    }


if __name__ == "__main__":
    result = validate(
        json.loads(ATLAS.read_text(encoding="utf-8")), read_recipes())
    print("EXP014 A03 REGIONAL FACILITY AUDIT:",
          json.dumps(result, sort_keys=True))
