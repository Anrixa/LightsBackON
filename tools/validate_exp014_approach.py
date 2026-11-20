#!/usr/bin/env python3
"""EXP014 A05 independent source audit: 25 real regional protocol structures.

This deliberately ignores sign text, artistic color, action titles and timer
values when measuring procedural diversity. It does NOT certify physical
routes, controller playability, real hardware, Steam or production saves.
"""
from __future__ import annotations

import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/gameplay/expedition_approach_intelligence.gd"
ATLAS = ROOT / "scenes/expeditions/atlas.json"
CONTINGENCIES = ROOT / "scenes/expeditions/site_contingencies_exp014_a02.json"
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"

ROW = re.compile(
    r'^\s*"(REG_\d{2})": \{"entry":"([ABC])", "first":"([ABC])", '
    r'"second":"([ABC])", "guard":"([a-z_]+)", '
    r'"protocol":"([a-z]+)", "recommend":"([a-z]+)", '
    r'"gap":(\d+), "window":(\d+)\},?$',
    re.MULTILINE,
)
GUARDS = {"logistics_solved", "faults_solved",
          "balancing_solved", "consequences_solved"}
PROTOCOLS = {"paired", "double", "triangulate", "timed", "isolate"}
ROUTES = {"priority", "resilience"}
# Domain-specific guard predicates are part of the actual gameplay proof.
# A04's environmental apparatus is independently authored against the
# same atlas hazard; this matrix rules out risk-incompatible guard splices.
RISK_GUARDS = {
    "depth": {"logistics_solved", "consequences_solved"},
    "conductivity": {"faults_solved", "logistics_solved"},
    "mechanical": {"balancing_solved", "logistics_solved"},
    "structure": {"consequences_solved", "logistics_solved"},
    "weather": {"faults_solved", "balancing_solved"},
}


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError("EXP014_A05_" + code)


def load_profiles(source: str | None = None) -> dict[str, dict]:
    script = SCRIPT.read_text(encoding="utf-8") if source is None else source
    found: dict[str, dict] = {}
    for region, entry, first, second, guard, protocol, recommended, gap, window in (
            ROW.findall(script)):
        require(region not in found, "DUPLICATED_PROFILE")
        found[region] = {
            "entry": entry, "first": first, "second": second,
            "guard": guard, "protocol": protocol, "recommend": recommended,
            "gap": int(gap), "window": int(window),
        }
    require(len(found) == 25, "PROFILE_COUNT")
    return found


def validate(atlas: dict, contingencies: dict, profiles: dict[str, dict],
             apparatus: dict[str, dict]) -> dict:
    levels, locations, regions = (
        atlas[key] for key in ("levels", "locations", "regions"))
    cases = contingencies.get("entries")
    require(len(levels) == len(locations) == 200 and len(regions) == 25,
            "ATLAS_COVERAGE")
    require(isinstance(cases, list) and len(cases) == 200, "CASE_COVERAGE")
    require(set(profiles) == set(apparatus)
            == {f"REG_{i:02d}" for i in range(1, 26)}, "REGION_COVERAGE")
    require(contingencies.get("qualification") == QUALIFICATION,
            "CASE_QUALIFICATION")
    fingerprints: set[tuple[str, ...]] = set()
    guards: set[str] = set()
    protocols: set[str] = set()
    chosen: set[str] = set()
    for ordinal, region in enumerate(regions, 1):
        rid = f"REG_{ordinal:02d}"
        require(region["id"] == rid, "REGION_ORDER")
        p = profiles[rid]
        require(p["entry"] in "ABC" and p["first"] in "ABC"
                and p["second"] in "ABC" and p["first"] != p["second"],
                "STATION_ROLE")
        require(p["guard"] in GUARDS and p["protocol"] in PROTOCOLS
                and p["recommend"] in ROUTES, "UNKNOWN_MECHANIC")
        require(2 <= p["gap"] <= 5 and 8 <= p["window"] <= 16,
                "TIME_BOUNDS")
        kind = apparatus[rid]["apparatus"]
        require(kind in RISK_GUARDS and p["guard"] in RISK_GUARDS[kind],
                "HAZARD_PROOF_MISMATCH")
        # Signage, action names, location titles and clocks are ignored.
        signature = tuple(p[k] for k in (
            "entry", "first", "second", "guard", "protocol", "recommend"))
        require(signature not in fingerprints, "MECHANICAL_SIGNATURE_REUSED")
        fingerprints.add(signature)
        guards.add(p["guard"])
        protocols.add(p["protocol"])
        chosen.add(p["recommend"])
    require(len(fingerprints) == 25 and len(protocols) == 5
            and len(guards) == 4 and len(chosen) == 2, "INSUFFICIENT_DIVERSITY")
    tasks: set[str] = set()
    sources: set[str] = set()
    for ordinal, (level, location, case) in enumerate(
            zip(levels, locations, cases), 1):
        lid = f"LV_{ordinal:03d}"
        loc = f"LOC_{ordinal:03d}"
        rid = f"REG_{(ordinal-1)//8+1:02d}"
        risk = regions[(ordinal-1)//8]["hazard"]
        require((level["id"], level["location_id"], level["region_id"])
                == (lid, loc, rid), "ATLAS_SOURCE_DRIFT")
        require((location["id"], location["district_id"], location["risk"])
                == (loc, rid, risk), "LOCATION_RISK_DRIFT")
        require(
            (case.get("level_id"), case.get("location_id"),
             case.get("region_id"), case.get("source_risk"),
             case.get("qualification"))
            == (lid, loc, rid, risk, QUALIFICATION),
            "CROSS_SOURCE_DRIFT",
        )
        expected_tasks = [f"JOB_{ordinal:03d}_{j}" for j in range(1, 6)]
        require([t["id"] for t in level["tasks"]] == expected_tasks
                and case.get("source_task_ids") == expected_tasks,
                "TASK_DRIFT")
        expected_targets = {
            key: f"SC_{ordinal:03d}_{key}" for key in "ABC"
        }
        require(case.get("targets") == expected_targets
                and case.get("recovery_target") == expected_targets["C"],
                "TARGET_DRIFT")
        require(lid not in sources and not tasks.intersection(expected_tasks),
                "DUPLICATED_SITE_OR_TASK")
        sources.add(lid)
        tasks.update(expected_tasks)
    return {
        "ok": True,
        "regional_behavioral_signatures": len(fingerprints),
        "evidence_protocol_families": len(protocols),
        "host_fact_guards": len(guards),
        "source_pinned_sites": len(sources),
        "source_pinned_original_tasks": len(tasks),
        "host_route_replay_cases": len(sources) * len(ROUTES),
        "original_tasks_mutated": False,
        "physical_playability_certified": False,
        "release_certified": False,
        "qualification": QUALIFICATION,
    }


if __name__ == "__main__":
    # Direct script invocation places tools/ on sys.path, not necessarily root.
    from validate_exp014_feedback import load_profiles as a04_profiles

    print("EXP014 A05 APPROACH INTELLIGENCE AUDIT:",
          json.dumps(validate(
              json.loads(ATLAS.read_text(encoding="utf-8")),
              json.loads(CONTINGENCIES.read_text(encoding="utf-8")),
              load_profiles(),
              a04_profiles(),
          ), sort_keys=True))
