#!/usr/bin/env python3
"""EXP015 A15: independent regional source integrity and release-hold closeout.

Only checks checked-in source and inherited regression coverage. Never elevates
headless evidence to physical, gameplay, Steam, or production release approval.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

if __package__:
    from . import qualify_exp014_a10 as baseline
    from . import exp015_stacked_qualification as stack
else:
    import qualify_exp014_a10 as baseline
    import exp015_stacked_qualification as stack

ROOT = Path(__file__).resolve().parents[1]
PHASE = "EXP015_A15"
REQUIRED_ROLES = (
    "entry", "first_route_a", "first_route_b", "first_rejoin",
    "second_route_a", "second_route_b", "second_rejoin", "finale",
)


def require(ok: bool, label: str, context: str = "") -> None:
    if not ok:
        raise ValueError(f"{PHASE}_{label}" + (f": {context}" if context else ""))


def load_sources(root: Path = ROOT) -> tuple[dict, dict]:
    return (
        json.loads((root / "scenes/expeditions/atlas.json").read_text(encoding="utf-8")),
        json.loads((root / "scenes/expeditions/regional_networks_exp014_a09.json")
                   .read_text(encoding="utf-8")),
    )


def audit_original_regions(atlas: dict, book: dict) -> dict[str, Any]:
    """Independently join exact 25*8 original source sites to 1000 immutable jobs."""
    regions = book["regions"]
    levels = atlas["levels"]
    require(len(atlas["regions"]) == 25 and len(regions) == 25,
            "REGIONAL_COUNT_MISMATCH")
    require(len(levels) == 200 and len(atlas["locations"]) == 200,
            "AUTHORING_SCOPE_MISMATCH")
    require(bool(atlas["legacy_campaign_contracts_unchanged"]),
            "LEGACY_SOURCE_UNLOCKED")
    require(bool(book["legacy_campaign_contracts_unchanged"]),
            "A09_LEGACY_SOURCE_UNLOCKED")
    by_level = {level["id"]: level for level in levels}
    require(len(by_level) == 200, "DUPLICATED_LEVEL_ID")
    atlas_regions = {region["id"] for region in atlas["regions"]}
    require(len(atlas_regions) == 25, "DUPLICATED_ATLAS_REGION")
    all_sites: set[str] = set()
    all_jobs: set[str] = set()
    all_regions: set[str] = set()
    total_feed_edges = 0
    total_ties = 0
    for index, region in enumerate(regions):
        region_id = f"REG_{index+1:02d}"
        require(region["region_id"] == region_id and region_id in atlas_regions,
                "WRONG_REGION_ORDER", region_id)
        require(region_id not in all_regions, "DUPLICATED_SOURCE_REGION", region_id)
        all_regions.add(region_id)
        sites = region["source_sites"]
        require(len(sites) == 8, "REGIONAL_SITE_COUNT", region_id)
        root = f"LV_{index*8+1:03d}"
        require(region["root_source_id"] == root, "WRONG_ROOT_SOURCE", region_id)
        local: set[str] = set()
        for offset, site in enumerate(sites):
            site_id = f"LV_{index*8+offset+1:03d}"
            require(site["site_id"] == site_id, "WRONG_SOURCE_SITE", site_id)
            require(site["campaign_role"] == REQUIRED_ROLES[offset],
                    "WRONG_CAMPAIGN_ROLE", site_id)
            require(site_id not in all_sites, "DUPLICATED_SOURCE_SITE", site_id)
            local.add(site_id)
            all_sites.add(site_id)
            level = by_level.get(site_id)
            require(level is not None, "MISSING_AUTHORED_LEVEL", site_id)
            require(level["region_id"] == region_id and
                    level["location_id"] == site["location_id"],
                    "SOURCE_LOCATION_DRIFT", site_id)
            task_ids = [task["id"] for task in level["tasks"]]
            require(len(task_ids) == 5 and len(set(task_ids)) == 5,
                    "AUTHORING_TASK_CARDINALITY", site_id)
            require(task_ids == site["source_task_ids"], "SOURCE_TASK_DRIFT", site_id)
            require(not all_jobs.intersection(task_ids), "DUPLICATED_JOB_ID", site_id)
            all_jobs.update(task_ids)
        incoming: dict[str, str] = {}
        for edge in region["primary_feeders"]:
            source, dest = edge["from"], edge["to"]
            require(source in local and dest in local and dest != root,
                    "INVALID_PRIMARY_ENDPOINT", region_id)
            require(dest not in incoming and source != dest,
                    "MULTIPLE_PRIMARY_FEEDERS", region_id)
            require(bool(edge["normally_closed"]) and int(edge["capacity_pu"]) > 0,
                    "PRIMARY_FEEDER_CAPACITY", region_id)
            incoming[dest] = source
        require(len(incoming) == 7 and root not in incoming,
                "PRIMARY_TREE_INCOMPLETE", region_id)
        for site in local - {root}:
            seen: set[str] = set()
            cursor = site
            while cursor != root:
                require(cursor in incoming and cursor not in seen,
                        "PRIMARY_TREE_LOOP_OR_ORPHAN", site)
                seen.add(cursor)
                cursor = incoming[cursor]
        for edge in region["standby_ties"]:
            require(edge["from"] in local and edge["to"] in local,
                    "INVALID_STANDBY_ENDPOINT", region_id)
            require(not edge["normally_closed"] and
                    edge["interlock"] == "break_before_make" and
                    int(edge["capacity_pu"]) > 0,
                    "UNSAFE_STANDBY_DEFAULT", region_id)
        require(set(region["strategies"]) == {"critical_first", "resilience_first"},
                "ORIGINAL_BRANCHES_MISSING", region_id)
        for strategy in region["strategies"].values():
            require(strategy["requires_receipt_site"] in local and
                    strategy["target_site"] in local,
                    "STRATEGY_REFERENCES_FOREIGN_SITE", region_id)
        total_feed_edges += len(incoming)
        total_ties += len(region["standby_ties"])
    require(len(all_sites) == 200 and len(all_jobs) == 1000,
            "SOURCE_COVERAGE_DRIFT")
    require(set(by_level) == all_sites, "LEVEL_SOURCE_SET_MISMATCH")
    return {
        "regions": len(all_regions), "locations": len(all_sites),
        "authored_levels": len(by_level), "source_task_ids": len(all_jobs),
        "original_primary_feeders": total_feed_edges,
        "original_break_before_make_ties": total_ties,
        "strategy_cases": 2 * len(all_regions),
        "source_graph_validation": "PASS",
    }


def qualify(root: Path = ROOT) -> dict[str, Any]:
    require(root.resolve() == ROOT.resolve(), "UNEXPECTED_ROOT")
    source = audit_original_regions(*load_sources(root))
    stacked = stack.qualify(root)
    protected = baseline.protected_git_audit()
    require(stacked["head_commit"] == protected["head_commit"], "HEAD_DRIFT")
    require(stacked["expected_methods"] >= 12, "INTEGRATION_TEST_INVENTORY_INCOMPLETE")
    require(not stacked["test_execution_proved_by_inventory"],
            "FAKE_TEST_EXECUTION_CERTIFICATION")
    require(all(x == "HOLD" for x in baseline.HOLDS.values()),
            "OWNER_RELEASE_HOLD_DRIFT")
    return {
        "phase": PHASE,
        "head_commit": stacked["head_commit"],
        "regional_source": source,
        "source_guard_methods_pinned": stacked["expected_methods"],
        "host_blob": stacked["source_host_object"],
        "protected_objects": protected["protected_objects"],
        "original_contracts_immutable": True,
        "ci_execution": "EXACT_HEAD_LINUX_AND_WINDOWS_EXTERNAL",
        "windows_export": "HEADLESS_EXPORTED_SMOKE_EXTERNAL",
        "independent_integration_review": "PENDING",
        "owner_holds": baseline.HOLDS.copy(),
        "ready_for_merge": False,
        "ready_for_release": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path,
                        default=Path("build/exp015-a15/qualification.json"))
    args = parser.parse_args()
    try:
        report = qualify()
    except (ValueError, KeyError, TypeError, OSError, baseline.QualificationError) as exc:
        print(f"[FAIL][{PHASE}] {exc}", flush=True)
        return 1
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                           encoding="utf-8")
    counts = report["regional_source"]
    print(f"[PASS][{PHASE}] regions={counts['regions']} levels={counts['authored_levels']} "
          f"jobs={counts['source_task_ids']} source_graph=PASS", flush=True)
    print(f"[HOLD][{PHASE}] exact-head CI, physical, Steam, independent review, "
          f"production and release not certified. report={args.report}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
