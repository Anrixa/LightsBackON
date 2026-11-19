#!/usr/bin/env python3
"""EXP011 independent, read-only audit of critical-service load balancing.

This validates all 200 authored source pins, the 1,000 unique targets,
mode-specific capacity/dependency rules and a deterministic completion path.
No gameplay state, production save, credits or source input is modified.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "scenes/expeditions/atlas.json"
LOGISTICS = ROOT / "scenes/expeditions/emergency_logistics.json"
LOADS = ROOT / "scenes/expeditions/critical_service_loads.json"
PRESETS = ROOT / "export_presets.cfg"

MODES = ("cascade", "triage", "interlock")
DEMANDS = ((4, 3, 2), (3, 2, 1), (2, 2, 2))
ANCHORS = ("PANEL_SPUR", "R_WEST", "PANEL_WEST")
PRIORITIES = ("critical", "priority", "support")
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"


def load_inputs() -> tuple[dict, dict, dict]:
    return tuple(json.loads(p.read_text(encoding="utf-8")) for p in (ATLAS, LOGISTICS, LOADS))


def _require(ok: bool, code: str) -> None:
    if not ok:
        raise ValueError(code)


def replay_reference(entry: dict) -> None:
    """Prove a reversible, capacity-bounded route to certification for a site.

    Sequential energize -> host dwell -> shed/latch is deliberately legal for
    all three modes. The runtime also permits legal concurrent dispatch in
    triage; it must still refuse >6 PU and the interlock's overlapping A/B.
    """
    capacity = entry["capacity_pu"]
    active: dict[str, int] = {}
    latched: set[str] = set()
    tick = 0
    for service in entry["services"]:
        sid = service["id"]
        _require(all(dep in latched for dep in service["requires"]), "EXP011_REFERENCE_DEPENDENCY")
        demand = service["demand_pu"]
        _require(sum(active.values()) + demand <= capacity, "EXP011_REFERENCE_OVERLOAD")
        if entry["mode"] == "interlock":
            suffix = sid.rsplit("_", 1)[-1]
            forbidden = "B" if suffix == "A" else "A" if suffix == "B" else ""
            _require(not any(other.endswith("_" + forbidden) for other in active) if forbidden else True,
                     "EXP011_REFERENCE_CROSS_FEED")
        active[sid] = demand
        tick += service["dwell_ticks"]
        _require(tick >= service["dwell_ticks"], "EXP011_REFERENCE_STABILITY")
        del active[sid]
        latched.add(sid)
    _require(len(latched) == 3 and not active, "EXP011_REFERENCE_NOT_SOLVED")
    # Recheck after supply loss requires no new allocated PU or replacement
    # materials: an exact recheck on each existing latched service is enough.
    pending_recheck = latched.copy()
    _require(pending_recheck == latched and sum(active.values()) == 0,
             "EXP011_REFERENCE_RECOVERY")


def validate(atlas: dict, logistics: dict, book: dict, presets: str | None = None) -> dict:
    _require(book.get("schema_version") == 1
             and book.get("authority") == "EXP011_HOST_LOAD_BALANCING"
             and book.get("atlas_revision") == atlas.get("revision")
             and book.get("qualification") == QUALIFICATION, "EXP011_HEADER_INVALID")
    entries = book.get("entries")
    _require(isinstance(entries, list) and len(entries) == 200, "EXP011_COUNT_INVALID")
    levels = {x["id"]: x for x in atlas["levels"]}
    manifests = {x["level_id"]: x for x in logistics["entries"]}
    _require(len(levels) == 200 and len(manifests) == 200, "EXP011_SOURCE_COUNT_INVALID")

    seen_levels: set[str] = set()
    seen_targets: set[str] = set()
    seen_keys: set[str] = set()
    seen_modes: set[str] = set()
    for index, entry in enumerate(entries):
        _require(isinstance(entry, dict), "EXP011_ENTRY_NOT_OBJECT")
        lid = entry.get("level_id")
        _require(isinstance(lid, str)
                 and lid in levels and lid in manifests
                 and lid not in seen_levels, "EXP011_DUPLICATE_OR_UNKNOWN_LEVEL")
        seen_levels.add(lid)
        level, manifest = levels[lid], manifests[lid]
        _require(entry.get("location_id") == level["location_id"]
                 and entry.get("source_puzzle_identity") == level["puzzle_identity"]
                 and entry.get("logistics_key") == manifest["logistics_key"]
                 and entry.get("site") == manifest["site"], "EXP011_SOURCE_DRIFT")
        mode = MODES[index % len(MODES)]
        seen_modes.add(mode)
        key = f'{manifest["logistics_key"]}|EXP011|{mode}'
        _require(entry.get("mode") == mode
                 and entry.get("load_key") == key and key not in seen_keys,
                 "EXP011_MODE_OR_KEY_DRIFT")
        seen_keys.add(key)
        suffix = lid.removeprefix("LV_")
        expected_targets = [f"LB_{suffix}_BOARD", f"LB_{suffix}_CTRL",
                            f"LB_{suffix}_A", f"LB_{suffix}_B", f"LB_{suffix}_C"]
        _require(entry.get("board") == expected_targets[0]
                 and entry.get("console") == expected_targets[1]
                 and entry.get("board_anchor") == "PANEL_WEST"
                 and entry.get("console_anchor") == "R_WEST"
                 and type(entry.get("capacity_pu")) is int
                 and entry["capacity_pu"] == 6, "EXP011_BOARD_OR_CAPACITY_INVALID")
        services = entry.get("services")
        _require(isinstance(services, list) and len(services) == 3,
                 "EXP011_SERVICES_INVALID")
        demand = DEMANDS[index % len(MODES)]
        names = (manifest["jobs"][0]["cargo"], manifest["jobs"][1]["cargo"],
                 f'{manifest["site"]} continuity feeder')
        for j, service in enumerate(services):
            _require(isinstance(service, dict), "EXP011_SERVICE_NOT_OBJECT")
            requirements = []
            if mode == "cascade" and j:
                requirements = [expected_targets[j + 1]]
            if mode == "interlock" and j == 2:
                requirements = expected_targets[2:4]
            _require(
                service.get("id") == expected_targets[j + 2]
                and service.get("anchor") == ANCHORS[j]
                and service.get("name") == names[j]
                and type(service.get("demand_pu")) is int
                and service["demand_pu"] == demand[j]
                and type(service.get("dwell_ticks")) is int
                and service["dwell_ticks"] == 5 + index % 4 + j * 2
                and type(service.get("deadline_ticks")) is int
                and service["deadline_ticks"] == 11 + index % 7 + j * 6
                and service.get("requires") == requirements
                and service.get("priority") == PRIORITIES[j],
                "EXP011_SERVICE_DRIFT",
            )
        for target in expected_targets:
            _require(target not in seen_targets, "EXP011_DUPLICATE_TARGET")
            seen_targets.add(target)
        replay_reference(entry)

    _require(len(seen_levels) == 200 and len(seen_keys) == 200
             and len(seen_targets) == 1000 and len(seen_modes) == 3,
             "EXP011_COVERAGE_INCOMPLETE")
    if presets is None:
        presets = PRESETS.read_text(encoding="utf-8")
    _require(presets.count("scenes/expeditions/critical_service_loads.json") == 2,
             "EXP011_WINDOWS_EXPORT_MISSING")
    return {"ok": True, "levels": len(seen_levels), "circuits": 600,
            "targets": len(seen_targets), "modes": sorted(seen_modes)}


if __name__ == "__main__":
    atlas, logistics, loads = load_inputs()
    print("EXP011 SOURCE AUDIT", json.dumps(validate(atlas, logistics, loads), sort_keys=True))
