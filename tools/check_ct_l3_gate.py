#!/usr/bin/env python3
"""Fail-closed Hill Road C09–C10 blueprint invariants; not a physical/Steam certification."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
C09 = Path("content/contracts/c09_wind_warning")
C10 = Path("content/contracts/c10_community_night")
TRACK = Path("docs/design/CT-L3-contract-track.json")
WEST = {"COMMUNITY_HALL": 6, "BAKERY": 4, "GREENHOUSE": 3}
EAST = {"FLATS": 5, "TELECOM_HUT": 4, "SERVICE_GARAGE": 3}


def load(root: Path, rel: Path, errors: list[str]) -> Any:
    try:
        return json.loads((root / rel).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        errors.append(f"{rel}: cannot load original-source data ({exc})")
        return None


def want(actual: Any, expected: Any, where: str, errors: list[str]) -> None:
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            errors.append(f"{where}: expected mapping")
            return
        for name, value in expected.items():
            if name not in actual:
                errors.append(f"{where}.{name}: missing")
            else:
                want(actual[name], value, f"{where}.{name}", errors)
    elif type(actual) is not type(expected) or actual != expected:
        errors.append(f"{where}: expected {expected!r}, got {actual!r}")


def by_id(rows: Any, label: str, errors: list[str]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    if not isinstance(rows, list):
        errors.append(f"{label}: expected list")
        return result
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            errors.append(f"{label}: invalid ID")
            continue
        if row["id"] in result:
            errors.append(f"{label}: duplicate ID {row['id']}")
        result[row["id"]] = row
    return result


def audit(root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    tracker = load(root, TRACK, errors)
    if not isinstance(tracker, dict):
        return errors
    tracked = {e.get("contract_id"): e for e in tracker.get("episodes", []) if isinstance(e, dict)}
    for cid, path in (("C09", C09), ("C10", C10)):
        grid = load(root, path / "grid.json", errors)
        mission = load(root, path / "mission.json", errors)
        if not isinstance(grid, dict) or not isinstance(mission, dict):
            continue
        nodes = by_id(grid.get("nodes"), cid + ".nodes", errors)
        edges = by_id(grid.get("edges"), cid + ".edges", errors)
        want(grid.get("contract_id"), cid, cid + ".grid.contract_id", errors)
        want(mission.get("contract_id"), cid, cid + ".mission.contract_id", errors)
        want(grid.get("trip_ticks"), 15, cid + ".trip_ticks", errors)
        want(nodes.get("GRID"), {"kind": "source", "capacity": 28}, cid + ".grid.GRID", errors)
        want(nodes.get("GEN"), {"kind": "source", "capacity": 6}, cid + ".grid.GEN", errors)
        for name, demand in {**WEST, **EAST}.items():
            want(nodes.get(name), {"kind": "consumer", "demand": demand},
                 f"{cid}.grid.{name}", errors)
        if not isinstance(mission.get("required_consumers"), list) or (
                len(mission["required_consumers"]) != 6 or
                set(mission["required_consumers"]) != set(WEST) | set(EAST)):
            errors.append(f"{cid}.mission.required_consumers: must be exactly six Hill services")
        record = tracked.get(cid)
        if not record or record.get("status") != "SOURCE_ALIGNED_HEADLESS_CANDIDATE":
            errors.append(f"{cid}.tracker.status: source-only acceptance required")
        if record is None or record.get("physical_release_status") != "HOLD":
            errors.append(f"{cid}.physical_release_status: HOLD required")
        if cid == "C09":
            want(edges.get("E_GRID_JW"), {"capacity": 14, "enabled": True}, "C09.west", errors)
            want(edges.get("E_GRID_JE"), {"capacity": 14, "healthy": False}, "C09.east", errors)
            want(mission.get("wind_routes"), {
                "warning_ticks": 600, "close_start_ticks": 900,
                "close_end_ticks": 1300, "roof_route": "ROUTE_ROOF",
                "ground_route": "ROUTE_GROUND", "safe_return": "ROUTE_SAFE_RETURN",
            }, "C09.wind_routes", errors)
        else:
            want(nodes.get("WEST"), {"failed": True, "tripped": True}, "C10.WEST", errors)
            want(nodes.get("EAST"), {"failed": False, "tripped": False}, "C10.EAST", errors)
            want(nodes.get("WEST_STAGE"), {"isolated": True}, "C10.WEST_STAGE", errors)
            want(nodes.get("STAGE"), {"kind": "consumer", "demand": 3, "enabled": True},
                 "C10.STAGE", errors)
            for key, data in {
                "E_GRID_WEST": {"capacity": 14}, "E_GRID_EAST": {"capacity": 14, "healthy": True},
                "E_GRID_STAGE": {"from": "GRID", "to": "STAGE_SPUR", "capacity": 4, "enabled": False},
                "E_STAGE_SPUR_STAGE": {"from": "STAGE_SPUR", "to": "STAGE", "capacity": 4},
                "E_WEST_STAGE": {"from": "WEST", "to": "WEST_STAGE", "capacity": 3},
            }.items():
                want(edges.get(key), data, f"C10.edges.{key}", errors)
            want(mission.get("access_latches"), [{
                "id": "LATCH_STAGE", "consumer": "STAGE", "source": "GRID",
                "supplied_ticks": 100, "grants": "STAGE_SERVICE_READY"}],
                "C10.access_latches", errors)
            want(mission.get("optional_timed_latch"), {
                "latch": "LATCH_STAGE", "deadline_ticks": 2400,
                "start_trigger": "mission_first_tick"}, "C10.optional_timed_latch", errors)
            want(mission.get("optional_latch_rewards"), ["LATCH_STAGE"],
                 "C10.optional_latch_rewards", errors)
            want(mission.get("optional_services"), [], "C10.optional_services", errors)
            repairs = load(root, path / "repairs.json", errors)
            if isinstance(repairs, dict):
                jobs = by_id(repairs.get("repairs"), "C10.repairs", errors)
                want(jobs.get("R_STAGE_SPUR"), {
                    "panel": "PANEL_STAGE", "isolate": "STAGE_SPUR",
                    "fix": {"op": "set", "id": "E_GRID_STAGE", "field": "enabled", "value": True}},
                    "C10.stage_install", errors)
    for cid in ("C11", "C12"):
        rec = tracked.get(cid)
        if rec is None or rec.get("status") != "NOT_STARTED":
            errors.append(f"{cid}: cannot claim an unimplemented mission")
        if rec is None or rec.get("physical_release_status") != "HOLD":
            errors.append(f"{cid}: physical release must remain HOLD")
    return errors


def main() -> int:
    print("[CT-L3][01/03] Check C09/C10 original blueprint grid/mission invariants")
    errors = audit()
    for message in errors:
        print("[CT-L3][FAIL]", message)
    print(f"CT_L3_SOURCE_GATE={'FAIL' if errors else 'PASS'} errors={len(errors)} contracts=2")
    print("[CT-L3][02/03] Stage event safety and bonus source are test-protected")
    print("[CT-L3][03/03] Physical, human, GPU, old-save, Steam/release HOLD")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
