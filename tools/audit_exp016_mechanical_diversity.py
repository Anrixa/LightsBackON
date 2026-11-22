#!/usr/bin/env python3
"""EXP016 A01: noncosmetic mechanic-diversity inventory for all 200 authored sites.

Read-only source inspection. It reports exact mechanically identical cases
instead of claiming that 200 distinct titles equal 200 distinct solutions.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path

if __package__:
    from .validate_exp014_contingencies import mechanic_signature
    from .validate_exp014_puzzles import signature as investigation_signature
else:
    from validate_exp014_contingencies import mechanic_signature
    from validate_exp014_puzzles import signature as investigation_signature

ROOT = Path(__file__).resolve().parents[1]
FILES = {
    "atlas": "scenes/expeditions/atlas.json",
    "contingency": "scenes/expeditions/site_contingencies_exp014_a02.json",
    "investigation": "scenes/expeditions/site_investigations_exp014_a08.json",
}
HOLDS = {
    "human_controller": "HOLD", "geometry_los": "HOLD",
    "physical_hardware": "HOLD", "steam_two_peer": "HOLD",
    "exp015_region_integration": "HOLD", "production_rewards_saves": "HOLD",
    "release": "HOLD",
}


def load(root: Path = ROOT) -> tuple[dict, dict, dict]:
    return tuple(json.loads((root / path).read_text(encoding="utf-8"))
                 for path in FILES.values())


def normalize(entry: dict, investigation: dict) -> tuple:
    """Exclude identifiers, prose, labels, durations and source-specific names."""
    return (
        mechanic_signature(entry, "priority"),
        mechanic_signature(entry, "resilience"),
        investigation_signature(investigation["branches"]["forensic"]),
        investigation_signature(investigation["branches"]["field"]),
    )


def fingerprint(spec: tuple) -> str:
    return hashlib.sha256(json.dumps(spec, sort_keys=True,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def audit(atlas: dict, contingencies: dict, investigations: dict) -> dict:
    levels = atlas["levels"]
    c = contingencies["entries"]
    inv = investigations["entries"]
    if len(levels) != 200 or len(c) != 200 or len(inv) != 200:
        raise ValueError("EXP016_A01_SOURCE_SET_INCOMPLETE")
    signatures: dict[str, list[str]] = defaultdict(list)
    region_fingerprints: dict[str, set[str]] = defaultdict(set)
    task_methods: Counter[str] = Counter()
    recovery_modes: Counter[str] = Counter()
    all_jobs: set[str] = set()
    dissimilar_branches = 0
    details = []
    for serial, (level, entry, inquiry) in enumerate(zip(levels, c, inv), start=1):
        lid = f"LV_{serial:03d}"
        region = f"REG_{(serial - 1) // 8 + 1:02d}"
        tasks = [t["id"] for t in level["tasks"]]
        expected_jobs = [f"JOB_{serial:03d}_{n}" for n in range(1, 6)]
        if (level["id"] != lid or entry["level_id"] != lid or
                inquiry["level_id"] != lid or level["region_id"] != region or
                inquiry["region_id"] != region or entry["region_id"] != region or
                tasks != expected_jobs or tasks != entry["source_task_ids"] or
                tasks != inquiry["source_task_ids"]):
            raise ValueError(f"EXP016_A01_SOURCE_DRIFT:{lid}")
        if all_jobs.intersection(tasks):
            raise ValueError(f"EXP016_A01_DUPLICATE_TASKS:{lid}")
        all_jobs.update(tasks)
        spec = normalize(entry, inquiry)
        fp = fingerprint(spec)
        signatures[fp].append(lid)
        region_fingerprints[region].add(fp)
        if mechanic_signature(entry, "priority") != mechanic_signature(entry, "resilience"):
            dissimilar_branches += 1
        for task in level["tasks"]:
            task_methods[task["mechanic"]] += 1
        for route in ("priority", "resilience"):
            recovery_modes.update(step["failure"] for step in entry["routes"][route])
        details.append({
            "level": lid, "region": region, "mechanic_fingerprint": fp,
            "objective_mechanics": [task["mechanic"] for task in level["tasks"]],
            "source_branch_differentiated": (
                mechanic_signature(entry, "priority") !=
                mechanic_signature(entry, "resilience")
            ),
        })
    if len(all_jobs) != 1000 or len(region_fingerprints) != 25:
        raise ValueError("EXP016_A01_TASK_OR_REGION_COUNT")
    collision_groups = sorted((sorted(group) for group in signatures.values()
                               if len(group) > 1),
                              key=lambda group: (-len(group), group[0]))
    return {
        "phase": "EXP016_A01",
        "source_parent": "EXP014_A10_4_NO_EXP015_CODE_REQUIRED",
        "levels": 200,
        "tasks": 1000,
        "regions": 25,
        "unique_combined_mechanical_signatures": len(signatures),
        "repeated_signature_groups": collision_groups,
        "levels_in_repeated_groups": sum(map(len, collision_groups)),
        "different_source_route_procedures": dissimilar_branches,
        "per_region_unique_fingerprints": {
            k: len(v) for k, v in sorted(region_fingerprints.items())
        },
        "source_objective_mechanics": dict(sorted(task_methods.items())),
        "recoverable_failure_modes": dict(sorted(recovery_modes.items())),
        "level_inventory": details,
        "uniqueness_measure_excludes": [
            "level IDs", "titles", "narrative", "station IDs",
            "action labels", "source timing and cosmetic values",
        ],
        "source_audit_is_not_player_or_release_certification": True,
        "owner_holds": HOLDS.copy(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path,
                        default=Path("build/exp016-a01/mechanical-diversity.json"))
    args = parser.parse_args()
    try:
        report = audit(*load())
    except (ValueError, KeyError, TypeError, OSError) as exc:
        print(f"[FAIL][EXP016_A01] {exc}", flush=True)
        return 1
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                           encoding="utf-8")
    print("[PASS][EXP016_A01] levels=200 tasks=1000 source_bound=true", flush=True)
    print("[MEASURE][EXP016_A01] distinct_structures=%d repeated_groups=%d "
          "affected_levels=%d" % (
              report["unique_combined_mechanical_signatures"],
              len(report["repeated_signature_groups"]),
              report["levels_in_repeated_groups"]), flush=True)
    print(f"[HOLD][EXP016_A01] EXP015 integration and physical gameplay deferred; "
          f"report={args.report}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
