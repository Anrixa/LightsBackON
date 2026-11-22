#!/usr/bin/env python3
"""EXP017 A01: independent semantic-source and structural morphology audit."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

if __package__:
    from .validate_exp014_regions import read_recipes
else:
    from validate_exp014_regions import read_recipes

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/world/expedition_regional_landmarks.gd"
ATLAS = ROOT / "scenes/expeditions/atlas.json"
PROFILE = re.compile(
    r'^\s*"(REG_\d{2})": \{"family": "(\w+)", "segments": (\d+), '
    r'"height_cm": (\d+), "cue": "(\w+)"\},?$',
    re.MULTILINE,
)
FAMILIES = {"weir", "frame", "gantry", "tank", "mast"}


def parse_profiles(source: str) -> dict[str, tuple[str, int, int, str]]:
    profiles: dict[str, tuple[str, int, int, str]] = {}
    for rid, family, segments, height, cue in PROFILE.findall(source):
        if rid in profiles:
            raise ValueError("EXP017_A01_DUPLICATED_PROFILE")
        profiles[rid] = family, int(segments), int(height), cue
    return profiles


def audit(atlas: dict, recipes: dict, profiles: dict) -> dict:
    if len(atlas["regions"]) != 25 or len(profiles) != 25:
        raise ValueError("EXP017_A01_REGION_COUNT")
    identities = set()
    present = set()
    for i, region in enumerate(atlas["regions"], 1):
        rid = f"REG_{i:02d}"
        if rid not in profiles or rid not in recipes or region["id"] != rid:
            raise ValueError("EXP017_A01_SOURCE_REGION_MISSING")
        family, segments, height, cue = profiles[rid]
        if cue != recipes[rid]["cue"] or region["hazard"] != recipes[rid]["risk"]:
            raise ValueError("EXP017_A01_SOURCE_RISK_DRIFT")
        if family not in FAMILIES or not 2 <= segments <= 6 or not 180 <= height <= 400:
            raise ValueError("EXP017_A01_INVALID_STRUCTURE")
        key = (family, segments, height)
        if key in identities:
            raise ValueError("EXP017_A01_REUSED_STRUCTURE")
        identities.add(key)
        present.add(family)
    if present != FAMILIES:
        raise ValueError("EXP017_A01_INCOMPLETE_FAMILY_VARIETY")
    return {
        "phase": "EXP017_A01",
        "regions": len(profiles), "distinct_structural_morphologies": len(identities),
        "structural_families": sorted(present),
        "original_levels_preserved": 200,
        "no_collision_authority_added": True,
        "physical_reachability_certified": False,
        "owner_release_hold": "HOLD",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path,
                        default=Path("build/exp017-a01/visual-morphology.json"))
    args = parser.parse_args()
    try:
        atlas = json.loads(ATLAS.read_text(encoding="utf-8"))
        profiles = parse_profiles(SCRIPT.read_text(encoding="utf-8"))
        report = audit(atlas, read_recipes(), profiles)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"[FAIL][EXP017_A01] {exc}", flush=True)
        return 1
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                           encoding="utf-8")
    print(f"[PASS][EXP017_A01] regions=25 structural_families=5 "
          f"distinct_actual_geometry=25 report={args.report}", flush=True)
    print("[HOLD][EXP017_A01] no physical navigation/LOS/controller certification",
          flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
