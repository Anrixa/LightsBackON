#!/usr/bin/env python3
"""Fail-closed C02-C06 original-blueprint source/receipt drift guard.

This checks authored source definitions and recorded evidence consistency only.
Live engine behavior, physical play, hardware, old saves and Steam have separate gates.
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
CONTRACT_DIRS = {
    "C02": "c02_dinner_rush",
    "C03": "c03_roof_route",
    "C04": "c04_whole_block",
    "C05": "c05_canal_pump_access",
    "C06": "c06_cold_chain",
}
ALDER = ["APT_E", "APT_W", "MARKET", "PUB", "WORKSHOP"]
CANAL = ["LAUNDRETTE", "DINER", "ROW_HOUSES", "DEPOT", "COLD_STORE", "PUMP_KIOSK"]

# Exact blueprint-sensitive facts. A subset match permits unrelated authored detail.
EXPECTED: dict[str, dict[str, Any]] = {
    "C02": {
        "nodes": {"GRID": {"capacity": 24}, "GEN": {"capacity": 6},
                  "JW": {"failed": True, "tripped": True}, "MARKET": {"demand": 5}, "PUB": {"demand": 4}},
        "edges": {"E_GRID_JE": {"healthy": False, "capacity": 12},
                  "E_TEMP_MARKET": {"capacity": 5, "enabled": False},
                  "E_TEMP_PUB": {"capacity": 4, "enabled": False}},
        "mission": {"required_consumers": ALDER, "opening_venues": {
            "consumers": ["MARKET", "PUB"], "supplied_ticks": 100,
            "deadline_ticks": 1800, "start_trigger": "briefing_dismissed_all_loaded",
            "permitted_sources": ["GRID", "GEN"]}},
        "required_pu": 20,
    },
    "C03": {
        "nodes": {"GRID": {"capacity": 24}, "GEN": {"capacity": 6},
                  "JW": {"failed": True}, "ROOF_BEACON": {"demand": 2},
                  "LADDER_LIGHT": {"demand": 1}},
        "edges": {"E_GRID_JE": {"healthy": False}, "E_GRID_ROOF": {"capacity": 12, "enabled": False},
                  "E_TEMP_ROOF_LIGHT": {"capacity": 2, "enabled": False}},
        "mission": {"required_consumers": ALDER, "access_latches": [
            {"id": "LATCH_LADDER_LIGHT", "consumer": "LADDER_LIGHT", "source": "GRID",
             "supplied_ticks": 50, "grants": "LADDER_LIGHT_READY"},
            {"id": "LATCH_ROOF_WORK_LIGHT", "consumer": "ROOF_BEACON", "source": "GEN",
             "supplied_ticks": 100, "grants": "ROOF_WORK_LIGHT_COMPLETE"}],
            "optional_latch_rewards": ["LATCH_ROOF_WORK_LIGHT"]},
        "required_pu": 20,
    },
    "C04": {
        "nodes": {"GRID": {"capacity": 24}, "SIGN": {"demand": 3}},
        "edges": {"E_GRID_SPUR": {"capacity": 4, "enabled": False},
                  "E_SPUR_SIGN": {"capacity": 4}},
        "mission": {"required_consumers": ALDER, "access_latches": [
            {"id": "LATCH_SIGN_SUPPLY", "consumer": "SIGN", "source": "GRID",
             "supplied_ticks": 100, "grants": "SIGN_CONTINUITY_COMPLETE"}],
            "optional_latch_rewards": ["LATCH_SIGN_SUPPLY"]},
        "required_pu": 20,
    },
    "C05": {
        "nodes": {"GRID": {"capacity": 30}, "GEN": {"capacity": 8},
                  "PUMP_WEST": {"demand": 5}, "PUMP_EAST": {"demand": 4},
                  "COLD_STORE": {"demand": 5}},
        "edges": {"E_GRID_WEST": {"capacity": 14, "healthy": False},
                  "E_GRID_EAST": {"capacity": 14, "healthy": False}},
        "mission": {"required_consumers": CANAL, "access_latches": [
            {"id": "LATCH_WEST_DRAIN", "consumer": "PUMP_WEST", "source": "GEN",
             "supplied_ticks": 120, "grants": "WEST_DRAINED"},
            {"id": "LATCH_EAST_DRAIN", "consumer": "PUMP_EAST", "source": "GEN",
             "supplied_ticks": 120, "grants": "EAST_DRAINED"}],
            "optional_pickup_deadline": {
                "consumer": "COLD_STORE", "deadline_ticks": 1800,
                "start_trigger": "first_equipment_pickup",
                "requires_latch": "LATCH_EAST_DRAIN"}},
        "required_pu": 25,
    },
    "C06": {
        "nodes": {"GRID": {"capacity": 30}, "GEN": {"capacity": 8},
                  "PUMP_EAST": {"demand": 4}, "COLD_STORE": {"demand": 5}},
        "edges": {"E_GRID_WEST": {"capacity": 14, "healthy": True},
                  "E_GRID_EAST": {"capacity": 14, "healthy": False},
                  "E_TEMP_PUMP_EAST": {"capacity": 4, "enabled": False},
                  "E_TEMP_COLD_STORE": {"capacity": 5, "enabled": False}},
        "mission": {"required_consumers": CANAL, "access_latches": [
            {"id": "LATCH_EAST_DRAIN", "consumer": "PUMP_EAST", "source": "GEN",
             "supplied_ticks": 120, "grants": "EAST_DRAINED"}],
            "optional_cumulative_outage": {
                "id": "COLD_CHAIN", "consumer": "COLD_STORE", "deadline_ticks": 1200,
                "permitted_sources": ["GRID", "GEN"]}},
        "required_pu": 25,
    },
}


def load(path: Path, errors: list[str]) -> Any:
    try:
        with path.open(encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError) as exc:
        errors.append(f"{path}: cannot load JSON: {exc}")
        return None


def match(actual: Any, expected: Any, path: str, errors: list[str]) -> None:
    """Compare dict subsets recursively, but preserve exact list and primitive semantics."""
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            errors.append(f"{path}: expected object")
            return
        for key, value in expected.items():
            if key not in actual:
                errors.append(f"{path}.{key}: missing")
            else:
                match(actual[key], value, f"{path}.{key}", errors)
    elif type(actual) is not type(expected) or actual != expected:
        errors.append(f"{path}: expected {expected!r}, got {actual!r}")


def indexed(rows: Any, label: str, errors: list[str]) -> dict[str, dict[str, Any]]:
    if not isinstance(rows, list):
        errors.append(f"{label}: expected array")
        return {}
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            errors.append(f"{label}: invalid ID row")
            continue
        if row["id"] in result:
            errors.append(f"{label}: duplicate ID {row['id']}")
        result[row["id"]] = row
    return result


def audit(root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    manifest = load(root / "docs/design/CT-BP-SOURCE-GATE.json", errors)
    tracker = load(root / "docs/design/CT-BLUEPRINT-CORRECTIONS.json", errors)
    if not isinstance(manifest, dict) or not isinstance(tracker, dict):
        return errors
    if manifest.get("level") != "SOURCE_ALIGNED_HEADLESS_CANDIDATE":
        errors.append("manifest: source level cannot be promoted")
    if not str(manifest.get("full_blueprint_release_certification", "")).startswith("HOLD"):
        errors.append("manifest: physical/release HOLD must remain explicit")
    receipts = indexed(manifest.get("contracts"), "manifest.contracts", errors)
    tracked = indexed(tracker.get("contracts"), "tracker.contracts", errors)
    if set(receipts) != set(EXPECTED) or set(tracked) != set(EXPECTED):
        errors.append("manifest/tracker contract IDs must be exactly C02-C06")
    sha_pattern = re.compile(r"[0-9a-f]{40}\Z")
    ci_pattern = re.compile(r"https://github\.com/Anrixa/LightsBackON/actions/runs/[0-9]+\Z")
    for cid, spec in EXPECTED.items():
        folder = root / "content/contracts" / CONTRACT_DIRS[cid]
        grid = load(folder / "grid.json", errors)
        mission = load(folder / "mission.json", errors)
        if isinstance(grid, dict) and isinstance(mission, dict):
            match(grid.get("contract_id"), cid, f"{cid}.grid.contract_id", errors)
            match(mission.get("contract_id"), cid, f"{cid}.mission.contract_id", errors)
            match(grid.get("trip_ticks"), 15, f"{cid}.trip_ticks", errors)
            nodes = indexed(grid.get("nodes"), f"{cid}.nodes", errors)
            edges = indexed(grid.get("edges"), f"{cid}.edges", errors)
            for ident, shape in spec["nodes"].items():
                match(nodes.get(ident), shape, f"{cid}.nodes.{ident}", errors)
            for ident, shape in spec["edges"].items():
                match(edges.get(ident), shape, f"{cid}.edges.{ident}", errors)
            match(mission, spec["mission"], f"{cid}.mission", errors)
            total = sum(nodes.get(ident, {}).get("demand", 0)
                        for ident in mission.get("required_consumers", [])
                        if isinstance(ident, str))
            match(total, spec["required_pu"], f"{cid}.required_pu", errors)
        r, t = receipts.get(cid), tracked.get(cid)
        if not r or not t:
            continue
        for fld in ("status",):
            match(r.get(fld), "SOURCE_ALIGNED_HEADLESS_CANDIDATE", f"{cid}.receipt.{fld}", errors)
        match(t.get("status"), "SOURCE_ALIGNED_HEADLESS_CANDIDATE", f"{cid}.tracker.status", errors)
        match(t.get("fidelity"), "SOURCE_ALIGNED_HEADLESS_CANDIDATE", f"{cid}.tracker.fidelity", errors)
        if not str(t.get("full_original_blueprint_certification", "")).startswith("HOLD"):
            errors.append(f"{cid}: physical original-blueprint certification must remain HOLD")
        fields = [("pr", "pull_request"), ("pr_final_head", "final_pr_head"),
                  ("pr_final_ci", "final_pr_ci_run"), ("merged_main_sha", "merged_main_sha"),
                  ("post_merge_ci", "post_merge_ci_run")]
        for left, right in fields:
            match(t.get(right), r.get(left), f"{cid}.tracker.{right}", errors)
        for key in ("pr_final_head", "merged_main_sha"):
            if not sha_pattern.fullmatch(str(r.get(key, ""))):
                errors.append(f"{cid}: malformed {key}")
        for key in ("pr_final_ci", "post_merge_ci"):
            if not ci_pattern.fullmatch(str(r.get(key, ""))):
                errors.append(f"{cid}: malformed {key}")
        if not isinstance(t.get("pending"), list) or not t["pending"]:
            errors.append(f"{cid}: must retain pending physical/release gates")
    return errors


def main() -> int:
    errors = audit()
    print("[CT-BP-GATE] Blueprint source invariants: C02 C03 C04 C05 C06")
    print("[CT-BP-GATE] Recorded PR/merge receipts: local consistency only")
    print("[CT-BP-GATE] Hardware/human/Steam/release certification: HOLD")
    for error in errors:
        print(f"[CT-BP-GATE][FAIL] {error}")
    print(f"CT_BP_SOURCE_GATE={'FAIL' if errors else 'PASS'} errors={len(errors)} contracts=5")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
