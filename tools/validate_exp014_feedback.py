#!/usr/bin/env python3
"""EXP014 A04 independent environmental-evidence/source integrity audit.

The three readouts are *visual evidence only*, rendered from host snapshots.
This script checks authoring and source linkage, not physical reachability,
controller feel, networking, player comprehension or release readiness.
"""
from __future__ import annotations

import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/world/expedition_environment_feedback.gd"
ATLAS = ROOT / "scenes/expeditions/atlas.json"
CONTINGENCIES = ROOT / "scenes/expeditions/site_contingencies_exp014_a02.json"
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
PROFILE = re.compile(
    r'^\s*"(REG_\d{2})": \{"apparatus":"([a-z]+)", "clues":'
    r'\[(".*?"," .*?")\]\},?$',
    re.MULTILINE,
)
# Parse only the literal one-line map entries. This deliberately rejects
# unknown formatting instead of silently ignoring an altered declaration.
ROW = re.compile(
    r'^\s*"(REG_\d{2})": \{"apparatus":"([a-z]+)", '
    r'"clues":\["([^"]+)","([^"]+)","([^"]+)"\]\},?$',
    re.MULTILINE,
)
APPARATUS = {"depth", "conductivity", "mechanical", "structure", "weather"}


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def load_profiles(source: str | None = None) -> dict[str, dict]:
    text = SCRIPT.read_text(encoding="utf-8") if source is None else source
    profiles: dict[str, dict] = {}
    for region, apparatus, first, second, third in ROW.findall(text):
        require(region not in profiles, "EXP014_A04_DUPLICATED_REGION")
        profiles[region] = {
            "apparatus": apparatus,
            "clues": (first, second, third),
        }
    require(len(profiles) == 25, "EXP014_A04_PROFILE_COUNT")
    return profiles


def validate(atlas: dict, contingencies: dict,
             profiles: dict[str, dict]) -> dict:
    regions, locations, levels = (
        atlas[key] for key in ("regions", "locations", "levels"))
    cases = contingencies.get("entries")
    require(len(regions) == 25 and len(locations) == 200
            and len(levels) == 200, "EXP014_A04_ATLAS_COVERAGE")
    require(isinstance(cases, list) and len(cases) == 200,
            "EXP014_A04_CONTINGENCY_COVERAGE")
    require(set(profiles) == {f"REG_{i:02d}" for i in range(1, 26)},
            "EXP014_A04_REGION_COVERAGE")
    require(contingencies.get("qualification") == QUALIFICATION,
            "EXP014_A04_UNQUALIFIED_CONTINGENCIES")
    unique_clues: set[str] = set()
    signatures: set[tuple] = set()
    for ordinal, region in enumerate(regions, 1):
        region_id = f"REG_{ordinal:02d}"
        require(region["id"] == region_id, "EXP014_A04_REGION_SEQUENCE")
        item = profiles[region_id]
        require(item["apparatus"] in APPARATUS,
                "EXP014_A04_UNKNOWN_EVIDENCE_APPARATUS")
        clues = item["clues"]
        require(len(clues) == 3 and all(len(c) >= 8 for c in clues),
                "EXP014_A04_SHORT_OR_MISSING_CLUE")
        require(len(set(clues)) == 3, "EXP014_A04_REPEATED_LOCAL_CLUE")
        require(not set(clues).intersection(unique_clues),
                "EXP014_A04_REUSED_REGIONAL_CLUE")
        unique_clues.update(clues)
        signatures.add((item["apparatus"], *clues))
    require(len(signatures) == 25 and len(unique_clues) == 75,
            "EXP014_A04_COSMETICALLY_DUPLICATED_SEQUENCE")
    sites: set[str] = set()
    tasks: set[str] = set()
    for ordinal, (level, location, case) in enumerate(
            zip(levels, locations, cases), 1):
        level_id = f"LV_{ordinal:03d}"
        loc_id = f"LOC_{ordinal:03d}"
        region_id = f"REG_{(ordinal - 1) // 8 + 1:02d}"
        risk = regions[(ordinal - 1) // 8]["hazard"]
        require(
            (level["id"], level["location_id"], level["region_id"])
            == (level_id, loc_id, region_id),
            "EXP014_A04_ATLAS_LEVEL_DRIFT",
        )
        require(
            (location["id"], location["district_id"], location["risk"])
            == (loc_id, region_id, risk),
            "EXP014_A04_LOCATION_RISK_DRIFT",
        )
        require(
            (case.get("level_id"), case.get("location_id"),
             case.get("region_id"), case.get("source_risk"))
            == (level_id, loc_id, region_id, risk),
            "EXP014_A04_CROSS_SOURCE_SPLICE",
        )
        require(case.get("qualification") == QUALIFICATION,
                "EXP014_A04_CASE_QUALIFICATION")
        expected_tasks = [f"JOB_{ordinal:03d}_{i}" for i in range(1, 6)]
        require(case.get("source_task_ids") == expected_tasks,
                "EXP014_A04_CASE_TASK_DRIFT")
        require([task["id"] for task in level["tasks"]] == expected_tasks,
                "EXP014_A04_ATLAS_TASK_DRIFT")
        require(level_id not in sites and
                not tasks.intersection(expected_tasks),
                "EXP014_A04_DUPLICATE_ID")
        sites.add(level_id)
        tasks.update(expected_tasks)
    return {
        "ok": True,
        "authored_regions": len(signatures),
        "environmental_evidence_signals": len(unique_clues),
        "apparatus_families": len({p["apparatus"] for p in profiles.values()}),
        "source_pinned_sites": len(sites),
        "original_task_ids_preserved": len(tasks),
        "host_authority_changed": False,
        "physical_playability_certified": False,
        "release_certified": False,
        "qualification": QUALIFICATION,
    }


if __name__ == "__main__":
    print("EXP014 A04 ENVIRONMENTAL FEEDBACK AUDIT:",
          json.dumps(
              validate(
                  json.loads(ATLAS.read_text(encoding="utf-8")),
                  json.loads(CONTINGENCIES.read_text(encoding="utf-8")),
                  load_profiles(),
              ),
              sort_keys=True,
          ))
