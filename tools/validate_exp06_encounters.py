#!/usr/bin/env python3
"""Independently verify EXP06's 200 committed encounters against EXP01.

This audit is deliberately read-only and needs only the Python standard library.
Its conclusions concern authored data integrity, not physical gameplay quality.
"""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ATLAS_PATH = ROOT / "scenes/expeditions/atlas.json"
ENCOUNTER_PATH = ROOT / "scenes/expeditions/bespoke_encounters.json"

FAMILIES = frozenset({
    "fault_trace", "feeder_pulse", "post_repair_audit", "stability_hold",
    "spur_isolation", "load_rebalance", "relay_coincidence", "circuit_pair",
})
HAZARDS = frozenset({
    "water_ingress", "gust_lockout", "static_discharge", "thermal_spike",
    "signal_interference", "mechanical_vibration", "dust_cloud",
    "equipment_condensation",
})
ROUTE_TO_FAMILY = {
    "switch_isolation": "spur_isolation",
    "generator_budget": "stability_hold",
    "alternative_feed": "circuit_pair",
    "route_test": "fault_trace",
    "dual_feed_lockout": "circuit_pair",
    "pump_sequence": "relay_coincidence",
    "staged_restart": "feeder_pulse",
    "transfer_route": "relay_coincidence",
    "prioritize_service": "post_repair_audit",
    "safe_load_shed": "load_rebalance",
}
CLIMATE_TO_HAZARD = {
    "rain": "water_ingress",
    "sea_fog": "equipment_condensation",
    "rail_vibration": "mechanical_vibration",
    "brackish_flood": "water_ingress",
    "freezing_rain": "equipment_condensation",
    "metal_dust": "dust_cloud",
    "river_silt": "water_ingress",
    "gate_surge": "mechanical_vibration",
    "spray": "equipment_condensation",
    "platform_storm": "gust_lockout",
    "motor_heat": "thermal_spike",
    "sea_ice": "equipment_condensation",
    "wave_surge": "water_ingress",
    "treefall": "gust_lockout",
    "ash": "dust_cloud",
    "isolation": "signal_interference",
    "glass_condensation": "equipment_condensation",
    "coal_seepage": "water_ingress",
    "spillway_rain": "water_ingress",
    "root_intrusion": "mechanical_vibration",
    "old_wiring": "static_discharge",
    "dye_mist": "equipment_condensation",
    "lightning": "static_discharge",
    "sandstorm": "dust_cloud",
    "stairwell_flood": "water_ingress",
}

SITES = frozenset({
    "distribution", "transport", "health", "commerce", "waterworks",
    "communications", "education", "shelter",
})


def _integer_in(value: Any, lower: int, upper: int) -> bool:
    """Reject booleans and fractional/out-of-bounds JSON numeric values."""
    return type(value) is int and lower <= value <= upper


def validate(atlas: dict[str, Any], book: dict[str, Any]) -> dict[str, Any]:
    """Raise ValueError for any source identity, parameter or diversity drift."""
    if (
        book.get("schema_version") != 1
        or book.get("authority") != "EXP06_HOST_PINNED_SOURCE_ONLY"
        or book.get("atlas_revision") != atlas.get("revision")
    ):
        raise ValueError("INVALID_BOOK_HEADER")
    levels = {level["id"]: level for level in atlas["levels"]}
    locations = {location["id"]: location for location in atlas["locations"]}
    entries = book.get("entries")
    if len(levels) != 200 or len(locations) != 200 or not isinstance(entries, list) or len(entries) != 200:
        raise ValueError("INVALID_ENCOUNTER_CARDINALITY")
    seen: set[str] = set()
    keys: set[str] = set()
    family_counts: Counter[str] = Counter()
    hazard_counts: Counter[str] = Counter()
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("MALFORMED_ENCOUNTER")
        level_id = entry.get("level_id")
        if level_id not in levels or level_id in seen:
            raise ValueError(f"FOREIGN_OR_DUPLICATE_LEVEL {level_id}")
        seen.add(level_id)
        level = levels[level_id]
        location = locations[level["location_id"]]
        expected = {
            "location_id": level["location_id"],
            "region_id": level["region_id"],
            "source_climate": location["climate"],
            "source_puzzle_identity": level["puzzle_identity"],
            "title": level["title"],
            "scene": location["environment"],
            "risk": location["risk"],
            "site": location["archetype"],
            "source_motifs": [t["mechanic"] for t in level["tasks"][:3]],
        }
        if any(entry.get(key) != value for key, value in expected.items()):
            raise ValueError(f"UNPINNED_ENCOUNTER {level_id}")
        key = entry.get("encounter_key")
        if not isinstance(key, str) or len(key) < 30 or key in keys or not key.startswith(level_id + "|"):
            raise ValueError(f"DUPLICATE_OR_INVALID_KEY {level_id}")
        keys.add(key)
        puzzle = entry.get("puzzle")
        hazard = entry.get("hazard")
        if not isinstance(puzzle, dict) or not isinstance(hazard, dict):
            raise ValueError(f"MISSING_PUZZLE_OR_HAZARD {level_id}")
        family = puzzle.get("family")
        hazard_kind = hazard.get("kind")
        if family not in FAMILIES or hazard_kind not in HAZARDS or entry.get("site") not in SITES:
            raise ValueError(f"UNSUPPORTED_FAMILY {level_id}")
        if family != ROUTE_TO_FAMILY.get(level["tasks"][1]["mechanic"]) or hazard_kind != CLIMATE_TO_HAZARD.get(location["climate"]):
            raise ValueError(f"UNPINNED_SOURCE_MECHANIC {level_id}")
        family_counts[family] += 1
        hazard_counts[hazard_kind] += 1
        if not all([
            _integer_in(puzzle.get("hold_ticks"), 140, 300),
            _integer_in(puzzle.get("min_gap_ticks"), 2, 30),
            _integer_in(puzzle.get("sync_ticks"), 90, 400),
            _integer_in(hazard.get("period_ticks"), 30, 180),
            _integer_in(hazard.get("active_ticks"), 1, 45),
            _integer_in(hazard.get("phase_offset"), 0, 180),
            hazard.get("blocks") in {"switches", "repairs", "both"},
        ]):
            raise ValueError(f"INVALID_PARAMETERS {level_id}")
        if hazard["active_ticks"] >= hazard["period_ticks"]:
            raise ValueError(f"NO_SAFE_WINDOW {level_id}")
        if any(word in entry for word in ("score", "client_success", "health_damage", "reward")):
            raise ValueError(f"UNAUTHORIZED_SIDE_EFFECT {level_id}")
    if seen != set(levels) or set(family_counts) != FAMILIES or set(hazard_counts) != HAZARDS:
        raise ValueError("MISSING_SOURCE_LEVEL_OR_VARIETY")
    return {
        "levels": len(seen),
        "unique_encounters": len(keys),
        "puzzle_families": dict(sorted(family_counts.items())),
        "hazard_families": dict(sorted(hazard_counts.items())),
        "authority": book["authority"],
        "physical_playability_certified": False,
    }


def main() -> int:
    atlas = json.loads(ATLAS_PATH.read_text(encoding="utf-8"))
    book = json.loads(ENCOUNTER_PATH.read_text(encoding="utf-8"))
    result = validate(atlas, book)
    print("EXP06_INDEPENDENT_SOURCE_AUDIT=PASS", json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
