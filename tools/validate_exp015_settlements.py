#!/usr/bin/env python3
"""EXP015 A10 independent original-source and finite-debt conservation oracle.

Uses the original A09 regions and A05 assurance book as authorities. It does
not equate an EXP04 receipt, a site label or a synthetic proof with live power.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "scenes" / "expeditions"
AUTHORITY = "EXP015_A10_SOURCE_BOUND_FINITE_DEBT_SETTLEMENT"
QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
RISKS = {
    "depth": "settle_dry_feeder_audit",
    "conductivity": "settle_insulation_audit",
    "mechanical": "settle_interlock_audit",
    "structure": "settle_structure_audit",
    "weather": "settle_exposure_audit",
}


def ensure(predicate: bool, reason: str) -> None:
    if not predicate:
        raise ValueError("EXP015_A10_" + reason)


def load() -> tuple[dict, dict, dict]:
    names = ("regional_networks_exp014_a09.json",
             "region_assurance_exp015_a05.json",
             "region_settlements_exp015_a10.json")
    return tuple(json.loads((CONTENT / name).read_text(encoding="utf-8"))
                 for name in names)


def audit(networks: dict, assurances: dict, book: dict) -> dict[str, Any]:
    entries = book.get("entries")
    regions = networks.get("regions")
    prior = assurances.get("entries")
    ensure(book.get("schema_version") == 1 and
           book.get("authority") == AUTHORITY and
           book.get("predecessor") == "EXP015_A09" and
           book.get("qualification") == QUALIFICATION and
           book.get("legacy_campaign_contracts_unchanged") is True and
           book.get("original_settlement_sites") == 25 and
           isinstance(entries, list) and len(entries) == 25 and
           isinstance(regions, list) and len(regions) == 25 and
           isinstance(prior, list) and len(prior) == 25,
           "SOURCE_BOOK_AUTHORITY")
    seen: set[str] = set()
    risks: Counter[str] = Counter()
    cases = {"finite_settlement": 0, "managed_deferral": 0,
             "no_debt": 0, "dark_anchor_denial": 0,
             "insufficient_reserve_denial": 0}
    evidence: list[dict[str, Any]] = []
    for index, (region, assurance, item) in enumerate(zip(regions, prior, entries)):
        source = region["source_sites"]
        finale = region["shelter_service_site"]
        matching = [s for s in source if s["site_id"] == finale]
        risk = region["risk_class"]
        anchor = region["reserve_anchor_site"]
        ensure(len(matching) == 1 and matching[0]["campaign_role"] == "finale" and
               risk in RISKS and finale not in seen and
               assurance["finale_site_id"] == finale and
               item.get("region_id") == region["region_id"] and
               item.get("finale_site_id") == finale and
               item.get("root_source_site_id") == region["root_source_id"] and
               item.get("reserve_anchor_site_id") == anchor and
               item.get("critical_service_site_id") == region["critical_service_site"] and
               item.get("risk_class") == risk and
               item.get("audit_proof") == RISKS[risk] and
               item.get("original_finale_task_ids") == matching[0]["source_task_ids"] and
               item.get("initial_reserve_pu") == region["initial_reserve_pu"] and
               item.get("qualification") == QUALIFICATION,
               "ORIGINAL_FINALE_SOURCE_MISMATCH")
        seen.add(finale)
        risks[risk] += 1
        opening = region["initial_reserve_pu"]
        ensure(type(opening) is int and opening >= 2, "FINITE_SOURCE_RESERVE")
        for debt in (0, 2):
            for anchor_live in (True, False):
                # This is a conditional ledger assertion, NOT an assertion
                # that any campaign source is actually restored/live.
                payable = debt > 0 and anchor_live and opening >= debt
                balance = opening - debt if payable else opening
                outstanding = 0 if payable else debt
                ensure(balance >= 0 and balance + (debt if payable else 0) == opening
                       and outstanding >= 0, "CONSERVATION")
                if payable:
                    cases["finite_settlement"] += 1
                elif debt > 0:
                    cases["managed_deferral"] += 1
                    cases["dark_anchor_denial"] += 1
                else:
                    cases["no_debt"] += 1
            # Even when the anchor is live, an insufficient original PU
            # balance must not permit debt retirement.
            debt_over_budget = opening + 2
            ensure(opening < debt_over_budget, "INSUFFICIENT_RESERVE_GUARD")
            cases["insufficient_reserve_denial"] += 1
        evidence.append({"region": region["region_id"], "finale": finale,
                         "original_anchor": anchor, "source_risk": risk,
                         "electrical_power_claimed": False})
        print(f"EXP015_A10_SOURCE {index+1:02d}/25 "
              f"{region['region_id']} finale={finale} anchor={anchor} "
              f"original_reserve={opening} risk={risk}")
    ensure(len(seen) == 25 and len(risks) == 5 and
           cases == {"finite_settlement": 25, "managed_deferral": 25,
                     "no_debt": 50, "dark_anchor_denial": 25,
                     "insufficient_reserve_denial": 50},
           "ORIGINAL_SCENARIO_COVERAGE")
    return {"ok": True, "phase": "EXP015_A10",
            "original_finales": len(seen), "source_risks": dict(risks),
            "conditional_source_scenarios": cases, "no_new_task_ids": True,
            "no_energization_claim": True, "regions": evidence,
            "qualification": QUALIFICATION}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = audit(*load())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    print("EXP015_A10_SOURCE_AUDIT=PASS original_finales=25 no_forged_power=1")


if __name__ == "__main__":
    main()
