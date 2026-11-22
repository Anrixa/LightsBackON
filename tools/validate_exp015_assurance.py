#!/usr/bin/env python3
"""EXP015 A05 independent original A09 critical-service/anchor-source oracle.

Recomputes restored/energized source sites from exact EXP05 route receipts.
An observed source-ready reserve recharge does not certify real electricity.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

if __package__:
    from .validate_exp015_aftercare import audit as audit_aftercare
    from .validate_exp015_finales import feeder_tree
else:
    from validate_exp015_aftercare import audit as audit_aftercare
    from validate_exp015_finales import feeder_tree

ROOT = Path(__file__).resolve().parents[1]
REGIONS = ROOT / "scenes/expeditions/regional_networks_exp014_a09.json"
FINALES = ROOT / "scenes/expeditions/region_finales_exp015_a03.json"
AFTERCARE = ROOT / "scenes/expeditions/region_aftercare_exp015_a04.json"
ASSURANCE = ROOT / "scenes/expeditions/region_assurance_exp015_a05.json"
HOLD = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
RISKS: dict[str, tuple[str, int]] = {
    "depth": ("dry_critical_feeder_clearance", 3),
    "conductivity": ("critical_insulation_proof", 5),
    "mechanical": ("critical_transfer_latch_proof", 2),
    "structure": ("critical_support_stability", 4),
    "weather": ("critical_exposure_reclearance", 3),
}


def demand(ok: bool, error: str) -> None:
    if not ok:
        raise ValueError("EXP015_A05_" + error)


def load() -> tuple[dict, dict, dict, dict]:
    return tuple(json.loads(path.read_text(encoding="utf-8"))
                 for path in (REGIONS, FINALES, AFTERCARE, ASSURANCE))


def original_supply(region: dict, strategy: str) -> dict[str, Any]:
    """No fake restored finale: only original route selection and receipts."""
    sites = [s["site_id"] for s in region["source_sites"]]
    slots = (0, 2, 3, 5, 6) if strategy == "critical_first" else (
        0, 1, 3, 4, 6)
    restored = {sites[index] for index in slots}
    energized = {sites[0]}
    for _ in range(len(sites)):
        for feeder in region["primary_feeders"]:
            if feeder["from"] in energized and feeder["to"] in restored:
                energized.add(feeder["to"])
    critical = region["critical_service_site"]
    anchor = region["reserve_anchor_site"]
    shelter_feeder = next(
        f for f in region["primary_feeders"]
        if f["to"] == region["shelter_service_site"])
    shelter_ready = shelter_feeder["from"] in energized
    reserve = region["initial_reserve_pu"]
    if strategy == "critical_first":
        reserve -= 2  # Actual A09 critical-first strategy.
        reserve -= 0 if shelter_ready else 2  # A03 buffered shelter.
    recharge_eligible = anchor in restored and anchor in energized
    recharge_gain = min(region["initial_reserve_pu"],
                        reserve + max(2, region["initial_reserve_pu"] // 2)) - reserve
    return {
        "critical_live": critical in energized,
        "anchor_restored": anchor in restored,
        "anchor_live": anchor in energized,
        "recharge_eligible": recharge_eligible,
        "recharge_gain_if_eligible": recharge_gain if recharge_eligible else None,
        "reserve_before_recharge": reserve,
        "finale_restored": region["shelter_service_site"] in restored,
    }


def audit(networks: dict, finales: dict, aftercare: dict,
          assurance: dict) -> dict[str, Any]:
    audit_aftercare(networks, finales, aftercare)
    demand(assurance.get("schema_version") == 1
           and assurance.get("authority") ==
           "EXP015_A05_ORIGINAL_CRITICAL_SERVICE_ASSURANCE"
           and assurance.get("predecessor") == "EXP015_A04"
           and assurance.get("qualification") == HOLD
           and assurance.get("original_campaign_unchanged") is True,
           "SOURCE_AUTHORITY")
    entries = assurance.get("entries", [])
    demand(isinstance(entries, list) and len(entries) == 25,
           "SOURCE_CARDINALITY")
    seen: set[str] = set()
    mechanics: set[str] = set()
    paths = {mode: {"critical_live": 0, "recharge_source_eligible": 0}
             for mode in ("critical_first", "resilience_first")}
    evidence = []
    for index, (region, prior, case) in enumerate(
            zip(networks["regions"], aftercare["entries"], entries)):
        sites, parents = feeder_tree(region)
        risk = region["risk_class"]
        critical_feeder = next(
            f for f in region["primary_feeders"]
            if f["to"] == region["critical_service_site"])
        demand(risk in RISKS and case.get("region_id") == region["region_id"]
               and case.get("finale_site_id") == sites[7]
               and case.get("finale_site_id") == prior["finale_site_id"]
               and sites[7] not in seen
               and case.get("critical_service_site") ==
               region["critical_service_site"]
               and case.get("critical_feeder_id") ==
               critical_feeder["edge_id"]
               and case.get("shelter_feeder_id") == prior["recovery_feeder_id"]
               and case.get("reserve_anchor_site") ==
               region["reserve_anchor_site"]
               and case.get("fault_signature") == region["fault_signature"]
               and case.get("recovery_procedure") ==
               region["recovery_procedure"]
               and case.get("risk_class") == risk
               and case.get("critical_retest_protocol") == RISKS[risk][0]
               and type(case.get("managed_pressure_pu")) is int
               and case["managed_pressure_pu"] == RISKS[risk][1]
               and case.get("source_qualification") == HOLD,
               "CRITICAL_ORIGINAL_BINDING")
        seen.add(sites[7])
        signature = (
            parents, sites.index(region["critical_service_site"]),
            sites.index(region["reserve_anchor_site"]),
            sites.index(critical_feeder["from"]),
            region["initial_reserve_pu"], risk,
        )
        digest = hashlib.sha256(repr(signature).encode("utf-8")).hexdigest()
        demand(digest not in mechanics, "RENAMED_TOPOLOGY_COLLISION")
        mechanics.add(digest)
        route_evidence = {}
        for mode, counts in paths.items():
            facts = original_supply(region, mode)
            route_evidence[mode] = facts
            counts["critical_live"] += int(facts["critical_live"])
            counts["recharge_source_eligible"] += int(facts["recharge_eligible"])
            demand(not facts["finale_restored"]
                   and facts["reserve_before_recharge"] >= 0,
                   "FAKE_RESTORATION_OR_RESERVE")
        evidence.append({"region_id": region["region_id"], "finale": sites[7],
                         "mechanical_sha256": digest, "paths": route_evidence})
        print(f"EXP015_A05_SOURCE {index+1:02}/25 {region['region_id']} "
              f"risk={risk} critical={route_evidence['critical_first']['critical_live']} "
              f"recharge={route_evidence['critical_first']['recharge_eligible']}")
    demand(len(seen) == len(mechanics) == 25, "SOURCE_COVERAGE")
    demand(paths["critical_first"] == {
        "critical_live": 25, "recharge_source_eligible": 3}
           and paths["resilience_first"] == {
               "critical_live": 0, "recharge_source_eligible": 0},
           "REGIONAL_RECEIPT_SOURCE_DRIFT")
    return {"ok": True, "phase": "EXP015_A05", "regions": 25,
            "original_branch_scenarios": 50, "risk_classes": len(RISKS),
            "distinct_original_mechanics": len(mechanics),
            "original_source_effects": paths, "qualification": HOLD,
            "original_levels_tasks_rewards_saves_unchanged": True,
            "physical_steam_hardware_release_certified": False,
            "evidence": evidence}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = audit(*load())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    print("EXP015_A05_SOURCE_PASS " + json.dumps({
        key: value for key, value in result.items() if key != "evidence"
    }, sort_keys=True))


if __name__ == "__main__":
    main()
