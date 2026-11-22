#!/usr/bin/env python3
"""EXP015 A04: verify the 25 authored real feeder-trip/standby recovery routes.

No generated gameplay awards, invented energization, human playability or release
certification. Predicted transfer feasibility uses original EXP05 receipt paths.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

# CLI is run by path; unittest imports this module as tools.validate_... .
if __package__:
    from .validate_exp015_finales import audit as audit_finales, feeder_tree
else:
    from validate_exp015_finales import audit as audit_finales, feeder_tree

ROOT = Path(__file__).resolve().parents[1]
REGIONAL = ROOT / "scenes/expeditions/regional_networks_exp014_a09.json"
FINALES = ROOT / "scenes/expeditions/region_finales_exp015_a03.json"
AFTERCARE = ROOT / "scenes/expeditions/region_aftercare_exp015_a04.json"
HOLD = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
RISK: dict[str, tuple[str, int]] = {
    "depth": ("trench_dryness_retest", 3),
    "conductivity": ("insulation_requalification", 5),
    "mechanical": ("load_latch_reinspection", 2),
    "structure": ("support_brace_reinspection", 4),
    "weather": ("exposed_span_clearance", 3),
}


def demand(condition: bool, name: str) -> None:
    if not condition:
        raise ValueError("EXP015_A04_" + name)


def load() -> tuple[dict, dict, dict]:
    return tuple(json.loads(path.read_text(encoding="utf-8"))
                 for path in (REGIONAL, FINALES, AFTERCARE))


def route(region: dict, mode: str) -> dict[str, Any]:
    """Recompute real source-side energized nodes, not receipt names alone."""
    sites = [site["site_id"] for site in region["source_sites"]]
    restored = {sites[i] for i in (
        (0, 2, 3, 5, 6) if mode == "critical_first" else
        (0, 1, 3, 4, 6))}
    live = {sites[0]}
    for _ in range(len(sites)):
        for feeder in region["primary_feeders"]:
            if feeder["from"] in live and feeder["to"] in restored:
                live.add(feeder["to"])
    shelter = region["shelter_service_site"]
    feeder = next(edge for edge in region["primary_feeders"]
                  if edge["to"] == shelter)
    ready = feeder["from"] in live
    reserve = region["initial_reserve_pu"]
    if mode == "critical_first":
        reserve -= 2  # Actual A09 select_strategy critical-first reserve cost
        if not ready:
            reserve -= 2  # A03 buffer at a dark shelter has actual reserve cost
    tie = region["standby_ties"][1]
    feasible = (tie["from"] in live and tie["to"] not in live
                and tie["capacity_pu"] >= 2 and reserve >= 2)
    return {
        "mode": mode,
        "reserve_after_a03_pu": reserve,
        "standby_source_live": tie["from"] in live,
        "standby_transfer_feasible": feasible,
        "managed_recovery_available": True,
        "standby_reserve_after_transfer_pu": reserve - 2 if feasible else None,
        "shelter_site_restored": shelter in restored,
    }


def audit(regional: dict, finales: dict, book: dict) -> dict[str, Any]:
    # The independently source-audited parent must qualify before this child.
    audit_finales(regional, finales)
    demand(book.get("schema_version") == 1
           and book.get("authority") ==
           "EXP015_A04_ORIGINAL_POST_FINALE_FEEDER_STRESS"
           and book.get("predecessor") == "EXP015_A03"
           and book.get("qualification") == HOLD
           and book.get("original_campaign_unchanged") is True,
           "BOOK_AUTHORITY")
    regions = regional["regions"]
    entries = book.get("entries", [])
    demand(isinstance(entries, list) and len(entries) == 25,
           "BOOK_CARDINALITY")
    seen: set[str] = set()
    signatures: set[str] = set()
    branch_counts = {
        "critical_first": {"standby_viable": 0, "managed_required": 0},
        "resilience_first": {"standby_viable": 0, "managed_required": 0},
    }
    evidence = []
    for i, (region, finale, entry) in enumerate(
            zip(regions, finales["entries"], entries)):
        sites, parents = feeder_tree(region)
        risk = region["risk_class"]
        demand(risk in RISK and
               entry.get("region_id") == region["region_id"] and
               entry.get("finale_site_id") == sites[7] and
               sites[7] not in seen and
               entry.get("shelter_service_site") == sites[7] and
               entry.get("critical_service_site") ==
               region["critical_service_site"] and
               entry.get("recovery_feeder_id") == finale["shelter_feeder_id"] and
               entry.get("standby_tie_id") ==
               region["standby_ties"][1]["edge_id"] and
               entry.get("fault_signature") == region["fault_signature"] and
               entry.get("recovery_procedure") ==
               region["recovery_procedure"] and
               entry.get("risk_class") == risk and
               entry.get("retest_protocol") == RISK[risk][0] and
               type(entry.get("managed_dark_pressure_pu")) is int and
               entry["managed_dark_pressure_pu"] == RISK[risk][1] and
               entry.get("source_qualification") == HOLD,
               "ORIGINAL_FEEDER_RECOVERY_BINDING")
        seen.add(sites[7])
        tie = region["standby_ties"][1]
        signature = (
            parents,
            sites.index(region["critical_service_site"]),
            sites.index(region["reserve_anchor_site"]),
            sites.index(tie["from"]),
            sites.index(tie["to"]),
            risk,
            region["initial_reserve_pu"],
        )
        signature_hash = hashlib.sha256(repr(signature).encode()).hexdigest()
        demand(signature_hash not in signatures, "MECHANICAL_COLLISION")
        signatures.add(signature_hash)
        paths = {}
        for mode, count in branch_counts.items():
            facts = route(region, mode)
            paths[mode] = facts
            count["standby_viable"] += int(facts["standby_transfer_feasible"])
            count["managed_required"] += int(not facts["standby_transfer_feasible"])
            demand(facts["reserve_after_a03_pu"] >= 0, "SOURCE_RESERVE_UNDERFLOW")
            # The original finale mission is not a forged completed receipt.
            demand(not facts["shelter_site_restored"], "PREMATURE_RESTORATION")
        evidence.append({
            "region": region["region_id"], "site": sites[7],
            "mechanical_sha256": signature_hash, "source_paths": paths,
        })
        print(f"EXP015_A04_SOURCE {i+1:02}/25 {region['region_id']} "
              f"risk={risk} distinct={signature_hash[:10]} "
              f"critical_transfer={paths['critical_first']['standby_transfer_feasible']} "
              f"resilience_transfer={paths['resilience_first']['standby_transfer_feasible']}")
    demand(len(seen) == len(signatures) == 25, "COVERAGE")
    demand(branch_counts["critical_first"]["standby_viable"] == 11
           and branch_counts["resilience_first"]["standby_viable"] == 17,
           "ORIGINAL_STANDBY_SOURCE_DRIFT")
    return {
        "ok": True, "phase": "EXP015_A04", "qualification": HOLD,
        "region_count": 25, "original_branch_scenarios": 50,
        "unique_source_topologies": len(signatures),
        "real_standby_feasibility": branch_counts,
        "original_levels_tasks_rewards_saves_unchanged": True,
        "physical_hardware_steam_release_qualified": False,
        "evidence": evidence,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    verdict = audit(*load())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(verdict, indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    print("EXP015_A04 SOURCE_PASS " + json.dumps({
        key: value for key, value in verdict.items() if key != "evidence"
    }, sort_keys=True))


if __name__ == "__main__":
    main()
