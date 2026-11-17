#!/usr/bin/env python3
"""Fail-closed structural audit of the C09 Hill Road original-blueprint authoring.

This is a source guard, not a simulation, human playtest or production approval.
Dynamic rules must also pass host-intent tests and the C01–C09 solution suite.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = Path("content/contracts/c09_wind_warning")
SOURCE = Path("docs/design/CT-L3-original-contract-sheets.json")
TRACKER = Path("docs/design/CT-L3-contract-track.json")
WEST = {"COMMUNITY_HALL": 6, "BAKERY": 4, "GREENHOUSE": 3}
EAST = {"FLATS": 5, "TELECOM_HUT": 4, "SERVICE_GARAGE": 3}
WIND = {
    "roof_entry": "ROUTE_ROOF_ENTRY",
    "roof_return": "ROUTE_ROOF_RETURN",
    "ground_route": "ROUTE_GROUND_SERVICE",
    "warning_ticks": 600,
    "closed_from_ticks": 900,
    "closed_through_ticks": 1300,
    "ground_extra_ticks": 200,
}
C09_BONUS = {
    "id": "LATCH_SHELTER_LIGHT",
    "consumer": "WORK_LIGHT",
    "source": "GEN",
    "supplied_ticks": 100,
    "grants": "SHELTER_LIGHT_READY",
}


def _read(root: Path, path: Path, errors: list[str]) -> Any:
    try:
        return json.loads((root / path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        errors.append(f"{path}: unreadable or malformed JSON ({exc})")
        return None


def _check(value: Any, expected: Any, label: str, errors: list[str]) -> None:
    if isinstance(expected, dict):
        if not isinstance(value, dict):
            errors.append(f"{label}: expected object")
            return
        for key, want in expected.items():
            if key not in value:
                errors.append(f"{label}.{key}: missing")
            else:
                _check(value[key], want, f"{label}.{key}", errors)
    elif type(value) is not type(expected) or value != expected:
        errors.append(f"{label}: expected {expected!r}, got {value!r}")


def _by_id(rows: Any, label: str, errors: list[str]) -> dict[str, dict[str, Any]]:
    if not isinstance(rows, list):
        errors.append(f"{label}: not an array")
        return {}
    seen: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            errors.append(f"{label}: invalid ID entry")
            continue
        ident = row["id"]
        if ident in seen:
            errors.append(f"{label}: duplicate ID {ident}")
        seen[ident] = row
    return seen


def audit(root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    source = _read(root, SOURCE, errors)
    tracker = _read(root, TRACKER, errors)
    grid = _read(root, CONTRACT / "grid.json", errors)
    mission = _read(root, CONTRACT / "mission.json", errors)
    equipment = _read(root, CONTRACT / "equipment.json", errors)
    if not all(isinstance(obj, dict) for obj in (source, tracker, grid, mission, equipment)):
        return errors

    _check(source.get("baseline"), {
        "district": "Hill Road", "grid_pu": 28, "generator_pu": 6,
        "feeder_west_pu": 14, "feeder_east_pu": 14,
        "west_services": WEST, "east_services": EAST, "required_pu": 25,
    }, "source.baseline", errors)
    _check(source.get("physical_certification"), "HOLD", "source.physical_certification", errors)
    _check(source.get("release_certification"), "HOLD", "source.release_certification", errors)
    sheets = _by_id(source.get("contracts"), "source.contracts", errors)
    if set(sheets) != {"C09", "C10", "C11", "C12"}:
        errors.append("source.contracts must contain exactly C09–C12")
    else:
        _check(sheets["C09"].get("wind"), {
            "warning_tick": 600, "roof_entry_closed_start_tick": 900,
            "roof_entry_closed_last_tick": 1300,
            "ground_additional_travel_target_ticks": 200, "safe_return": True,
        }, "source.C09.wind", errors)
        _check(sheets["C10"].get("stage"), {
            "demand_pu": 3, "installed_direct_spur_capacity_pu": 4,
            "west_if_local_stage_pu": 16, "final_grid_pu": 28,
            "bonus_supplied_ticks": 100, "bonus_deadline_ticks": 2400,
        }, "source.C10.stage", errors)
        _check(sheets["C11"].get("garage_control"), {
            "demand_pu": 4, "access_latch_ticks": 100,
        }, "source.C11.access", errors)
        _check(sheets["C11"].get("optional"), {
            "max_uninterrupted_telecom_outage_ticks": 50, "fail_when_greater": True,
        }, "source.C11.optional", errors)
        _check(sheets["C12"].get("lighting_stagger_ticks"), 20, "source.C12.stagger", errors)
        _check(sheets["C12"].get("final_grid_pu"), 28, "source.C12.grid", errors)

    _check(grid.get("contract_id"), "C09", "grid.contract_id", errors)
    _check(mission.get("contract_id"), "C09", "mission.contract_id", errors)
    _check(grid.get("trip_ticks"), 15, "grid.trip_ticks", errors)
    nodes = _by_id(grid.get("nodes"), "grid.nodes", errors)
    edges = _by_id(grid.get("edges"), "grid.edges", errors)
    _check(nodes.get("GRID"), {"kind": "source", "capacity": 28}, "grid.GRID", errors)
    _check(nodes.get("GEN"), {"kind": "source", "capacity": 6}, "grid.GEN", errors)
    _check(nodes.get("WEST"), {"failed": True, "tripped": True}, "grid.WEST", errors)
    _check(edges.get("E_GRID_WEST"), {"capacity": 14, "healthy": True}, "grid.west_feeder", errors)
    _check(edges.get("E_GRID_EAST"), {"capacity": 14, "healthy": False}, "grid.east_feeder", errors)
    _check(nodes.get("WORK_LIGHT"), {"kind": "consumer", "demand": 2}, "grid.work_light", errors)
    _check(edges.get("E_TEMP_WORK_LIGHT"), {"capacity": 2, "enabled": False}, "grid.temp_light", errors)
    for ident, pu in {**WEST, **EAST}.items():
        _check(nodes.get(ident), {"kind": "consumer", "demand": pu}, f"grid.{ident}", errors)
    required = mission.get("required_consumers")
    if not isinstance(required, list) or len(required) != 6 or set(required) != set(WEST) | set(EAST):
        errors.append("mission.required_consumers must be six exact Hill Road services")
    _check(mission.get("wind_window"), WIND, "mission.wind_window", errors)
    _check(mission.get("access_latches"), [C09_BONUS], "mission.access_latches", errors)
    _check(mission.get("optional_latch_rewards"), ["LATCH_SHELTER_LIGHT"], "mission.optional_rewards", errors)
    _check(mission.get("optional_services"), [], "mission.optional_services", errors)
    fixed = _by_id(mission.get("fixed_ladders"), "mission.fixed_ladders", errors)
    if set(fixed) != {"ROUTE_ROOF_ENTRY", "ROUTE_ROOF_RETURN", "ROUTE_GROUND_SERVICE"}:
        errors.append("mission.fixed_ladders must keep three distinct safety routes")
    elif fixed["ROUTE_ROOF_ENTRY"].get("grants") != fixed["ROUTE_GROUND_SERVICE"].get("grants"):
        errors.append("mission: ground and roof must grant the same east repair access")
    anchors = _by_id(equipment.get("anchors"), "equipment.anchors", errors)
    if "PAD_SHELTER" not in anchors or anchors["PAD_SHELTER"].get("routes") != ["E_TEMP_WORK_LIGHT"]:
        errors.append("equipment.PAD_SHELTER: work light must have one authorized socket")
    for contract in tracker.get("episodes", []):
        if contract.get("contract_id") in ("C10", "C11", "C12") and contract.get("status") != "NOT_STARTED":
            errors.append(f"{contract['contract_id']}: cannot mark unimplemented contract complete")
        if contract.get("physical_release_status") != "HOLD":
            errors.append(f"{contract.get('contract_id')}: physical/release HOLD must remain")
    return errors


def main() -> int:
    print("[CT-L3/01] Audit Hill Road original-blueprint source authority")
    print("[CT-L3/02] Check network topology, bonus, wind and source sheets")
    errors = audit()
    for error in errors:
        print("[CT-L3][FAIL]", error)
    print(f"CT_L3_SOURCE_GATE={'FAIL' if errors else 'PASS'} errors={len(errors)}")
    print("CT_L3_HARDWARE_STEAM_RELEASE=HOLD")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
