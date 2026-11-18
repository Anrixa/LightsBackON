#!/usr/bin/env python3
"""Rebuild/check the authored EXP01 district atlas from compact reviewable seeds.

--check (default) is read-only and CI-safe.
--write explicitly replaces only scenes/expeditions/atlas.json, after creating
a timestamped backup when the file already exists; unrelated content is untouched.

The 12 existing host contracts and personal rewards are deliberately unaffected.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SEEDS = ROOT / "docs/design/EXP01-atlas-seeds.json"
ATLAS = ROOT / "scenes/expeditions/atlas.json"

SLOTS = [
    "distribution", "transport", "health", "commerce", "waterworks",
    "communications", "education", "shelter",
]
STAGES = [
    "investigation", "power_routing", "field_repair",
    "optional_discovery", "restoration",
]
STAGE_TITLES = [
    "Investigate", "Plan the feed", "Repair under lock",
    "Optional discovery", "Prove restoration",
]
TOOLS = [
    "meter", "switchboard", "repair_kit", "field_archive", "host_verification",
]
POINTS = [35, 50, 65, 30, 80]
TROPHIES = [
    "dispatch ledger", "enamel badge", "night map", "signal tag",
    "etched token",
]
DECKS = [
    "Crew logs", "Circuit tokens", "Found objects",
    "Maintenance stamps", "Archived notices",
]


def create_atlas(seeds: dict[str, Any]) -> dict[str, Any]:
    """Deterministic, explicit mission-brief construction; no randomized filler."""
    regions: list[dict[str, Any]] = []
    locations: list[dict[str, Any]] = []
    levels: list[dict[str, Any]] = []
    for d, region in enumerate(seeds["regions"]):
        reg_id = region["id"]
        regions.append({
            "id": reg_id,
            "name": region["name"],
            "setting": region["setting"],
            "hazard": region["hazard"],
            "palette": region["palette"],
            "climate": region["climate"],
            "category": "district_candidate",
        })
        for j, name in enumerate(region["sites"]):
            n = d * 8 + j + 1
            loc_id = f"LOC_{n:03d}"
            lvl_id = f"LV_{n:03d}"
            arc_idx = (d * 13 + j * 7 + n) % len(seeds["puzzle_names"])
            arc = seeds["puzzle_names"][arc_idx]
            twist = seeds["twists"][(d * 5 + j * 3) % len(seeds["twists"])]
            phase = (n * 7 + d) % len(seeds["evidence"])
            slot = SLOTS[j]
            reveal = (
                f"The {region['setting']} have left {twist} at {name}. "
                f"{region['hazard'][0].upper()}{region['hazard'][1:]} threatens "
                f"{slot} infrastructure; solve the {arc} without sacrificing "
                "neighboring services."
            )
            locations.append({
                "id": loc_id,
                "district_id": reg_id,
                "name": name,
                "archetype": slot,
                "climate": region["climate"],
                "environment": region["setting"],
                "risk": region["hazard"],
                "palette": region["palette"],
                "story_hook": twist,
                "hero_prop": f"{slot} landmark at {name}",
                "planning_anchor_cm": [(j % 4) * 1100 + 200, (j // 4) * 1350 + 250],
                "production_status": "UNBUILT_LOCATION",
            })
            task_text = [
                seeds["evidence"][(phase + j) % 15],
                seeds["route"][(phase + d) % 15],
                seeds["repair"][(phase + j * 2) % 15],
                seeds["optional"][(phase + d * 2) % 15],
                seeds["finish"][(phase + j + d) % 15],
            ]
            mechanics = seeds["action_sets"][(d + j * 3) % 10]
            tasks = []
            for k, kind in enumerate(STAGES):
                task_id = f"JOB_{n:03d}_{k + 1}"
                tasks.append({
                    "id": task_id,
                    "ordinal": k + 1,
                    "kind": kind,
                    "required": k != 3,
                    "mechanic": mechanics[k],
                    "tool": TOOLS[k],
                    "title": f"{STAGE_TITLES[k]} — {name}",
                    "briefing": (
                        f"{task_text[k]} at {name}. Account for {region['hazard']}; "
                        + ("this discovery is optional and cannot block extraction"
                           if k == 3 else
                           "the host must confirm this work before the shift advances")
                        + "."
                    ),
                    "field_points_preview": POINTS[k] + (arc_idx % 5) * 5,
                    "timing_hint_ticks": (
                        100 + (d % 4) * 25 if k == 4
                        else (90 + (j % 5) * 20 if k == 3 else 0)
                    ),
                    "status": "DESIGN_ONLY_NOT_HOST_ENABLED",
                })
            collectible = {
                "id": f"FIND_{n:03d}",
                "name": f"{name} {TROPHIES[n % len(TROPHIES)]}",
                "set": DECKS[(d + j) % len(DECKS)],
                "discovery_task_id": tasks[3]["id"],
                "rarity": "authored_story",
                "effect": "LORE_ONLY_NO_POWER_OR_CREDITS",
                "status": "PLANNED_NOT_COLLECTIBLE",
            }
            levels.append({
                "id": lvl_id,
                "location_id": loc_id,
                "region_id": reg_id,
                "title": f"{name}: {arc[0].upper()}{arc[1:]}",
                "mission_hook": reveal,
                "puzzle_identity": f"{arc}/{region['climate']}/{slot}",
                "hazard": region["hazard"],
                "tier": 1 + ((n // 24) % 5),
                "estimated_task_count": 5,
                "original_campaign_id": None,
                "tasks": tasks,
                "collectible": collectible,
                "scoring_authority": "PREVIEW_POINTS_ONLY",
                "runtime_status": "DESIGN_BRIEFING_ONLY",
            })
    return {
        "schema_version": 1,
        "revision": "EXP01-2026-11-19",
        "authority": "DESIGN_PREVIEW_ONLY_NOT_GAMEPLAY",
        "legacy_campaign_contracts_unchanged": True,
        "scope": {
            "regions": 25, "locations": 200, "levels": 200,
            "tasks": 1000, "collectibles": 200,
        },
        "regions": regions,
        "locations": locations,
        "levels": levels,
    }


def encoded(data: dict[str, Any]) -> bytes:
    return (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true", help="Read-only regeneration comparison (default).")
    group.add_argument("--write", action="store_true", help="Back up and explicitly replace the atlas.")
    args = parser.parse_args(argv)
    print(f"EXP01_STAGE=SEEDS READ path={SEEDS} ", flush=True)
    seeds = json.loads(SEEDS.read_text(encoding="utf-8"))
    data = create_atlas(seeds)
    expected = encoded(data)
    print(
        "EXP01_STAGE=GENERATE regions=%d locations=%d levels=%d tasks=%d bytes=%d"
        % (len(data["regions"]), len(data["locations"]), len(data["levels"]),
           sum(len(level["tasks"]) for level in data["levels"]), len(expected)),
        flush=True,
    )
    digest = hashlib.sha256(expected).hexdigest()
    if not args.write:
        if not ATLAS.is_file():
            print(f"EXP01_GATE=FAIL missing={ATLAS}", file=sys.stderr)
            return 1
        actual = ATLAS.read_bytes()
        if actual != expected:
            print(
                f"EXP01_GATE=FAIL generator_drift expected_sha256={digest} "
                f"actual_sha256={hashlib.sha256(actual).hexdigest()} file={ATLAS}",
                file=sys.stderr,
            )
            return 1
        print(f"EXP01_GATE=PASS mode=READ_ONLY sha256={digest} file={ATLAS}", flush=True)
        return 0

    ATLAS.parent.mkdir(parents=True, exist_ok=True)
    if ATLAS.is_file() and ATLAS.read_bytes() == expected:
        print(f"EXP01_GATE=UNCHANGED sha256={digest} file={ATLAS}", flush=True)
        return 0
    if ATLAS.is_file():
        suffix = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        backup = ATLAS.with_name(f"{ATLAS.name}.backup-{suffix}")
        if backup.exists():
            print(f"EXP01_GATE=FAIL backup_would_collide={backup}", file=sys.stderr)
            return 1
        shutil.copy2(ATLAS, backup)
        print(f"EXP01_STAGE=BACKUP path={backup}", flush=True)
    tmp = ATLAS.with_suffix(".json.tmp")
    with tmp.open("wb") as handle:
        handle.write(expected)
        handle.flush()
        import os
        os.fsync(handle.fileno())
    tmp.replace(ATLAS)
    print(f"EXP01_GATE=WRITTEN sha256={digest} file={ATLAS}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
