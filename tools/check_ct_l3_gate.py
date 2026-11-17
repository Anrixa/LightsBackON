#!/usr/bin/env python3
"""Fail-closed C09–C12 Hill Road original-blueprint source invariants.

This structural audit complements runtime host replays and negative tests.
It never certifies physical scenes, human/controller, GPU, old saves or Steam.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
C09 = Path("content/contracts/c09_wind_warning")
C10 = Path("content/contracts/c10_community_night")
C11 = Path("content/contracts/c11_borrowed_power")
C12 = Path("content/contracts/c12_lights_back_on")
TRACK = Path("docs/design/CT-L3-contract-track.json")
CONTRACTS = {"C09": C09, "C10": C10, "C11": C11, "C12": C12}
WEST = {"COMMUNITY_HALL": 6, "BAKERY": 4, "GREENHOUSE": 3}
EAST = {"FLATS": 5, "TELECOM_HUT": 4, "SERVICE_GARAGE": 3}
SOURCE_STATUS = "SOURCE_ALIGNED_HEADLESS_CANDIDATE"


def load(root: Path, rel: Path, errors: list[str]) -> Any:
    try:
        return json.loads((root / rel).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        errors.append(f"{rel}: cannot load original-source data ({exc})")
        return None


def want(actual: Any, expected: Any, where: str, errors: list[str]) -> None:
    """Compare exact scalars and lists; allow extra fields in source mappings."""
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            errors.append(f"{where}: expected mapping")
            return
        for key, expected_value in expected.items():
            if key not in actual:
                errors.append(f"{where}.{key}: missing")
            else:
                want(actual[key], expected_value, f"{where}.{key}", errors)
    elif type(actual) is not type(expected) or actual != expected:
        errors.append(f"{where}: expected {expected!r}, got {actual!r}")


def by_id(rows: Any, label: str, errors: list[str]) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    if not isinstance(rows, list):
        errors.append(f"{label}: expected list")
        return out
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            errors.append(f"{label}: invalid ID")
            continue
        if row["id"] in out:
            errors.append(f"{label}: duplicate ID {row['id']}")
        out[row["id"]] = row
    return out


def audit(root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    tracker = load(root, TRACK, errors)
    if not isinstance(tracker, dict):
        return errors

    episodes = by_id(tracker.get("episodes"), "CT-L3.episodes", errors)
    tracked: dict[str, dict[str, Any]] = {}
    for record in episodes.values():
        cid = record.get("contract_id")
        if not isinstance(cid, str) or cid in tracked:
            errors.append(f"CT-L3 tracker: invalid or duplicate contract_id {cid!r}")
            continue
        tracked[cid] = record

    for cid, directory in CONTRACTS.items():
        grid = load(root, directory / "grid.json", errors)
        mission = load(root, directory / "mission.json", errors)
        repairs = load(root, directory / "repairs.json", errors)
        solution = load(root, directory / "solution.json", errors)
        if not all(isinstance(doc, dict) for doc in (grid, mission, repairs, solution)):
            continue

        nodes = by_id(grid.get("nodes"), f"{cid}.nodes", errors)
        edges = by_id(grid.get("edges"), f"{cid}.edges", errors)
        jobs = by_id(repairs.get("repairs"), f"{cid}.repairs", errors)
        rec = tracked.get(cid)
        if not rec or rec.get("status") != SOURCE_STATUS:
            errors.append(f"{cid}.tracker.status: source-only candidate required")
        if not rec or rec.get("physical_release_status") != "HOLD":
            errors.append(f"{cid}.physical_release_status: HOLD required")
        if rec and rec.get("acceptance_ceiling") != SOURCE_STATUS:
            errors.append(f"{cid}.acceptance_ceiling: source-only required")
        want(grid.get("contract_id"), cid, f"{cid}.grid.contract_id", errors)
        want(mission.get("contract_id"), cid, f"{cid}.mission.contract_id", errors)
        want(repairs.get("contract_id"), cid, f"{cid}.repairs.contract_id", errors)
        want(solution.get("contract_id"), cid, f"{cid}.solution.contract_id", errors)
        if not isinstance(solution.get("steps"), list) or len(solution["steps"]) < 20:
            errors.append(f"{cid}.solution.steps: expected full host trace")
        want(grid.get("trip_ticks"), 15, f"{cid}.trip_ticks", errors)
        want(nodes.get("GRID"), {"kind": "source", "capacity": 28}, f"{cid}.grid.GRID", errors)
        want(nodes.get("GEN"), {"kind": "source", "capacity": 6}, f"{cid}.grid.GEN", errors)
        for name, demand in {**WEST, **EAST}.items():
            want(nodes.get(name), {"kind": "consumer", "demand": demand},
                 f"{cid}.grid.{name}", errors)
        required = mission.get("required_consumers")
        if not isinstance(required, list) or len(required) != 6 or set(required) != set(WEST) | set(EAST):
            errors.append(f"{cid}.mission.required_consumers: exactly six Hill services required")
        for edge in edges.values():
            if edge.get("from") not in nodes or edge.get("to") not in nodes:
                errors.append(f"{cid}.edges.{edge['id']}: orphan endpoint")

        if cid == "C09":
            want(edges.get("E_GRID_JW"), {"capacity": 14, "enabled": True}, "C09.west", errors)
            want(edges.get("E_GRID_JE"), {"capacity": 14, "healthy": False}, "C09.east", errors)
            want(mission.get("wind_routes"), {
                "warning_ticks": 600, "close_start_ticks": 900, "close_end_ticks": 1300,
                "roof_route": "ROUTE_ROOF", "ground_route": "ROUTE_GROUND",
                "safe_return": "ROUTE_SAFE_RETURN",
            }, "C09.wind_routes", errors)
        elif cid == "C10":
            want(nodes.get("WEST"), {"failed": True, "tripped": True}, "C10.WEST", errors)
            want(nodes.get("EAST"), {"failed": False, "tripped": False}, "C10.EAST", errors)
            want(nodes.get("WEST_STAGE"), {"isolated": True}, "C10.WEST_STAGE", errors)
            want(nodes.get("STAGE"), {"kind": "consumer", "demand": 3, "enabled": True}, "C10.STAGE", errors)
            for name, desired in {
                "E_GRID_WEST": {"capacity": 14}, "E_GRID_EAST": {"capacity": 14, "healthy": True},
                "E_GRID_STAGE": {"from": "GRID", "to": "STAGE_SPUR", "capacity": 4, "enabled": False},
                "E_STAGE_SPUR_STAGE": {"from": "STAGE_SPUR", "to": "STAGE", "capacity": 4},
                "E_WEST_STAGE": {"from": "WEST", "to": "WEST_STAGE", "capacity": 3},
            }.items():
                want(edges.get(name), desired, f"C10.edges.{name}", errors)
            want(mission.get("access_latches"), [{
                "id": "LATCH_STAGE", "consumer": "STAGE", "source": "GRID",
                "supplied_ticks": 100, "grants": "STAGE_SERVICE_READY"}],
                "C10.access_latches", errors)
            want(mission.get("optional_timed_latch"),
                {"latch": "LATCH_STAGE", "deadline_ticks": 2400, "start_trigger": "mission_first_tick"},
                "C10.optional_timed_latch", errors)
            want(mission.get("optional_latch_rewards"), ["LATCH_STAGE"], "C10.optional_latch_rewards", errors)
            want(mission.get("optional_services"), [], "C10.optional_services", errors)
            want(jobs.get("R_STAGE_SPUR"), {
                "panel": "PANEL_STAGE", "isolate": "STAGE_SPUR",
                "fix": {"op": "set", "id": "E_GRID_STAGE", "field": "enabled", "value": True}},
                "C10.stage_install", errors)
        elif cid == "C11":
            want(nodes.get("WEST"), {"failed": False, "tripped": False}, "C11.WEST", errors)
            want(nodes.get("GARAGE_CONTROL"), {"kind": "consumer", "demand": 4}, "C11.GARAGE_CONTROL", errors)
            for name, desired in {
                "E_GRID_WEST": {"capacity": 14}, "E_GRID_EAST": {"capacity": 14, "healthy": False},
                "E_GEN_TEMP": {"capacity": 6},
                "E_WEST_TELECOM": {"from": "WEST", "to": "TELECOM_HUT", "capacity": 4, "enabled": False},
                "E_TEMP_TELECOM": {"from": "TEMP", "to": "TELECOM_HUT", "capacity": 4, "enabled": False},
                "E_TEMP_GARAGE": {"from": "TEMP", "to": "GARAGE_CONTROL", "capacity": 4, "enabled": False},
            }.items():
                want(edges.get(name), desired, f"C11.edges.{name}", errors)
            want(mission.get("access_latches"), [{
                "id": "LATCH_GARAGE_CONTROL", "consumer": "GARAGE_CONTROL",
                "source": "GEN", "supplied_ticks": 100, "grants": "EAST_CONTROL_READY"}],
                "C11.access_latches", errors)
            want(mission.get("optional_max_consecutive_outage"), {
                "id": "TELECOM_CONTINUITY", "consumer": "TELECOM_HUT",
                "max_outage_ticks": 50, "permitted_sources": ["GRID", "GEN"]},
                "C11.optional_max_consecutive_outage", errors)
            want(jobs.get("R_EAST_TRUNK"), {
                "access": "EAST_CONTROL_READY",
                "fix": {"op": "set", "id": "E_GRID_EAST", "field": "healthy", "value": True}},
                "C11.east_repair", errors)
        elif cid == "C12":
            want(nodes.get("WEST"), {"failed": True, "tripped": True}, "C12.WEST", errors)
            want(nodes.get("BEACON"), {"kind": "consumer", "demand": 3}, "C12.BEACON", errors)
            want(nodes.get("DRAIN_CONTROL"), {"kind": "consumer", "demand": 4}, "C12.DRAIN_CONTROL", errors)
            want(nodes.get("WEST_BEACON"), {"isolated": True}, "C12.WEST_BEACON", errors)
            for name, desired in {
                "E_GRID_WEST": {"capacity": 14}, "E_GRID_EAST": {"capacity": 14, "healthy": False},
                "E_GEN_TEMP": {"capacity": 6},
                "E_TEMP_CONTROL": {"from": "TEMP", "to": "DRAIN_CONTROL", "capacity": 4, "enabled": False},
                "E_GRID_BEACON": {"from": "GRID", "to": "BEACON_SPUR", "capacity": 4, "enabled": False},
                "E_BEACON_SPUR_BEACON": {"from": "BEACON_SPUR", "to": "BEACON", "capacity": 4},
                "E_WEST_BEACON": {"from": "WEST", "to": "WEST_BEACON", "capacity": 3},
            }.items():
                want(edges.get(name), desired, f"C12.edges.{name}", errors)
            want(mission.get("access_latches"), [
                {"id": "LATCH_DRAIN", "consumer": "DRAIN_CONTROL", "source": "GEN",
                 "supplied_ticks": 120, "grants": "EAST_DRAINED"},
                {"id": "LATCH_BEACON", "consumer": "BEACON", "source": "GRID",
                 "supplied_ticks": 100, "grants": "BEACON_READY"},
            ], "C12.access_latches", errors)
            want(mission.get("optional_latch_rewards"), ["LATCH_BEACON"],
                 "C12.optional_latch_rewards", errors)
            want(mission.get("finale"), {
                "trigger": "first_verified", "stagger_ticks": 20,
                "radio_subtitle_key": "radio.c12.restored",
                "results_actions": ["replay", "remaining_optional_tasks"],
            }, "C12.finale", errors)
            want(jobs.get("R_EAST_TRUNK"), {
                "access": "EAST_DRAINED",
                "fix": {"op": "set", "id": "E_GRID_EAST", "field": "healthy", "value": True}},
                "C12.east_repair", errors)
            want(jobs.get("R_BEACON_SPUR"), {
                "panel": "PANEL_BEACON", "isolate": "BEACON_SPUR",
                "fix": {"op": "set", "id": "E_GRID_BEACON", "field": "enabled", "value": True}},
                "C12.beacon_install", errors)
    return errors


def main() -> int:
    print("[CT-L3][01/04] Read source tracker and original Hill Road contracts")
    errors = audit()
    for error in errors:
        print("[CT-L3][FAIL]", error)
    print(f"CT_L3_SOURCE_GATE={'FAIL' if errors else 'PASS'} errors={len(errors)} contracts=4")
    print("[CT-L3][02/04] C09/C10/C11/C12 source-sensitive invariants checked")
    print("[CT-L3][03/04] Host replays, negative tests and cross-language checks run separately")
    print("[CT-L3][04/04] Physical/controller/GPU/old-save/Steam/release HOLD")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
