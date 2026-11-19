#!/usr/bin/env python3
"""EXP010 independent, read-only audit of emergency supply manifests.

Pins every logistics target and cargo to the 200 EXP01/EXP009 source scenarios.
Contains no network, production persistence, economy or test-side mutations.
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "scenes/expeditions/atlas.json"
CHAINS = ROOT / "scenes/expeditions/consequence_chains.json"
MANIFESTS = ROOT / "scenes/expeditions/emergency_logistics.json"
ROUTES = {"direct": {"spares": 2, "fuel": 1, "ticks": 6},
          "relay": {"spares": 1, "fuel": 2, "ticks": 14}}
CARGO = {
    "distribution": ("Grid reconnection sleeve", "Priority feeder stabilizer"),
    "transport": ("Crossing signal isolator", "Platform traction control pack"),
    "health": ("Cold-chain transfer cassette", "Sterile room safety module"),
    "commerce": ("Protected archive bus coupler", "Market emergency light kit"),
    "waterworks": ("Sluice backflow seal", "Flood pump emergency control"),
    "communications": ("Relay synchronization module", "Emergency antenna switchgear"),
    "education": ("Workshop circuit isolator", "Campus evacuation controller"),
    "shelter": ("Shelter heating link", "Emergency exit transfer assembly"),
}
PATTERNS = ("serial", "triage", "crossdock")


def load_inputs() -> tuple[dict, dict, dict]:
    return tuple(json.loads(p.read_text(encoding="utf-8"))
                 for p in (ATLAS, CHAINS, MANIFESTS))


def replay_reference(manifest: dict) -> None:
    """Independent finite-stock oracle, including recall and both delivery routes."""
    stock = dict(manifest["stock"])
    assert stock == {"spares": 3, "fuel": 3}
    # A crossdock dispatch must use relay first; other patterns allow either
    # ordering, but never two identical routes with insufficient finite stock.
    routes = ("relay", "direct") if manifest["pattern"] == "crossdock" else ("direct", "relay")
    for job, route in zip(manifest["jobs"], routes):
        recipe = ROUTES[route]
        if manifest["pattern"] == "crossdock" and job["priority"] == "critical":
            assert route == "relay"
        assert all(stock[k] >= recipe[k] for k in ("spares", "fuel"))
        stock = {k: stock[k] - recipe[k] for k in ("spares", "fuel")}
        assert recipe["ticks"] > 0
    assert stock == {"spares": 0, "fuel": 0}

    # A recalled *unreceived* shipment must restore the whole recipe exactly
    # once, leaving the original manifest possible to finish.
    reserve = dict(manifest["stock"])
    direct = ROUTES["direct"]
    for k in reserve:
        reserve[k] -= direct[k]
        reserve[k] += direct[k]
    assert reserve == manifest["stock"]


def validate(atlas: dict, chains: dict, book: dict) -> dict:
    if (book.get("schema_version") != 1
            or book.get("authority") != "EXP010_HOST_LOGISTICS"
            or book.get("atlas_revision") != atlas.get("revision")):
        raise ValueError("EXP010_HEADER_INVALID")
    levels = {level["id"]: level for level in atlas["levels"]}
    chain_map = {chain["level_id"]: chain for chain in chains["entries"]}
    entries = book.get("entries")
    if (not isinstance(entries, list) or len(entries) != 200
            or len(levels) != 200 or len(chain_map) != 200):
        raise ValueError("EXP010_LEVEL_COUNT_INVALID")
    seen: set[str] = set()
    keys: set[str] = set()
    targets: set[str] = set()
    sites: Counter[str] = Counter()
    patterns: Counter[str] = Counter()
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise ValueError("EXP010_ENTRY_NOT_OBJECT")
        lid = entry.get("level_id")
        if lid not in levels or lid not in chain_map or lid in seen:
            raise ValueError("EXP010_DUPLICATE_OR_FOREIGN_LEVEL")
        seen.add(lid)
        chain, level = chain_map[lid], levels[lid]
        pins = {
            "location_id": level["location_id"],
            "source_puzzle_identity": level["puzzle_identity"],
            "chain_key": chain["chain_key"],
            "scenario_key": chain["scenario_key"],
            "site": chain["site"],
        }
        if any(entry.get(k) != v for k, v in pins.items()):
            raise ValueError("EXP010_SOURCE_DRIFT")
        pattern = PATTERNS[index % 3]
        if entry.get("pattern") != pattern:
            raise ValueError("EXP010_PATTERN_DRIFT")
        patterns[pattern] += 1
        sites[chain["site"]] += 1
        key = chain["chain_key"] + "|EXP010|" + pattern
        if entry.get("logistics_key") != key or key in keys:
            raise ValueError("EXP010_LOGISTICS_KEY_INVALID")
        keys.add(key)
        suffix = lid.removeprefix("LV_")
        depot, console = f"LG_{suffix}_DEPOT", f"LG_{suffix}_CTRL"
        if (entry.get("depot") != depot or entry.get("console") != console
                or entry.get("depot_anchor") != "PANEL_WEST"
                or entry.get("console_anchor") != "R_WEST"
                or entry.get("stock") != {"spares": 3, "fuel": 3}):
            raise ValueError("EXP010_STOCK_OR_DEPOT_INVALID")
        jobs = entry.get("jobs")
        if not isinstance(jobs, list) or len(jobs) != 2:
            raise ValueError("EXP010_JOBS_INVALID")
        expected_targets = (depot, console)
        for j, job in enumerate(jobs):
            job_id = f"LG_{suffix}_{'AB'[j]}"
            expected = {
                "id": job_id,
                "anchor": ("PANEL_SPUR", "R_WEST")[j],
                "cargo": CARGO[chain["site"]][j],
                "linked_service": chain["nodes"][j + 1]["id"],
                "deadline_ticks": (18 + index % 6) if j == 0 else (36 + index % 9),
                "requires": f"LG_{suffix}_A" if j == 1 and pattern == "serial" else "",
                "priority": "critical" if j == 0 else "support",
            }
            if job != expected:
                raise ValueError("EXP010_JOB_SOURCE_INVALID")
            expected_targets += (job_id,)
        for target in expected_targets:
            if target in targets:
                raise ValueError("EXP010_DUPLICATE_TARGET")
            targets.add(target)
        replay_reference(entry)
    if (len(seen) != 200 or len(keys) != 200 or len(targets) != 800
            or len(sites) != 8 or dict(patterns) != {"serial": 67, "triage": 67, "crossdock": 66}):
        raise ValueError("EXP010_COVERAGE_INCOMPLETE")
    presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    if presets.count("scenes/expeditions/emergency_logistics.json") != 2:
        raise ValueError("EXP010_WINDOWS_EXPORT_MISSING")
    return {"ok": True, "levels": len(seen), "jobs": len(seen) * 2,
            "targets": len(targets), "domains": len(sites),
            "patterns": dict(patterns)}


def main() -> int:
    atlas, chains, book = load_inputs()
    print("EXP010 SOURCE AUDIT", json.dumps(validate(atlas, chains, book), sort_keys=True))
    print("HOLD: human/controller physical playability, Windows GPU/Steam and release")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
