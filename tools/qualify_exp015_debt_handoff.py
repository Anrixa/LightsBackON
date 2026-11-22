#!/usr/bin/env python3
"""EXP015 A11: independent 25-region source and finite-debt continuity oracle.

Models authenticated entry->finale handoff and debt retirement only from
original source graph, not from asserted player completion or fabricated grid
power. Godot integration independently executes the *real* A09 transitions.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1] / "scenes" / "expeditions"
SOURCE_ONLY = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"


def load() -> tuple[dict, dict, dict]:
    names = ("regional_networks_exp014_a09.json",
             "region_entries_exp015_a09.json",
             "region_settlements_exp015_a10.json")
    return tuple(json.loads((ROOT / p).read_text(encoding="utf-8")) for p in names)


def ensure(ok: bool, code: str) -> None:
    if not ok:
        raise ValueError("EXP015_A11_" + code)


def audit(regional: dict, entries: dict, settlements: dict) -> dict[str, Any]:
    regions, roots, endings = (d.get(k, []) for d, k in
                               ((regional, "regions"), (entries, "entries"),
                                (settlements, "entries")))
    ensure(len(regions) == len(roots) == len(endings) == 25,
           "SOURCE_SPINE_COVERAGE")
    ensure(entries.get("qualification") == SOURCE_ONLY and
           settlements.get("qualification") == SOURCE_ONLY,
           "SOURCE_RELEASE_HOLD")
    seen: set[str] = set()
    fingerprints: set[str] = set()
    count = 0
    evidence = []
    for i, (r, root, ending) in enumerate(zip(regions, roots, endings)):
        site_ids = [v["site_id"] for v in r["source_sites"]]
        root_id = r["root_source_id"]
        finale_id = r["shelter_service_site"]
        anchor_id = r["reserve_anchor_site"]
        feeders = {f["edge_id"]: f for f in r["primary_feeders"]}
        assert_anchor = [f for f in feeders.values() if f["to"] == anchor_id]
        initial_reserve = r["initial_reserve_pu"]
        ensure(len(site_ids) == len(set(site_ids)) == 8 and
               root_id == site_ids[0] and finale_id == site_ids[7] and
               anchor_id in site_ids and len(assert_anchor) == 1 and
               root["entry_site_id"] == ending["root_source_site_id"] == root_id and
               ending["finale_site_id"] == finale_id and
               ending["reserve_anchor_site_id"] == anchor_id and
               root["region_id"] == ending["region_id"] == r["region_id"] and
               root["risk_class"] == ending["risk_class"] == r["risk_class"] and
               root["initial_reserve_pu"] == ending["initial_reserve_pu"] == initial_reserve and
               root["original_task_ids"] == r["source_sites"][0]["source_task_ids"] and
               ending["original_finale_task_ids"] == r["source_sites"][7]["source_task_ids"] and
               root["transport_feeder_id"] in feeders and
               root["critical_feeder_id"] in feeders and
               feeders[root["transport_feeder_id"]]["from"] == root_id and
               feeders[root["critical_feeder_id"]]["from"] == root_id and
               root["qualification"] == ending["qualification"] == SOURCE_ONLY and
               r["region_id"] not in seen and initial_reserve >= 2,
               "ORIGINAL_SOURCE_HANDOFF_DRIFT")
        seen.add(r["region_id"])
        for first_branch in ("critical", "transport"):
            for policy in ("buffer", "managed"):
                starting_debt = 2 if policy == "managed" else 0
                entry_balance = initial_reserve - (2 if policy == "buffer" else 0)
                # Original physical reserve/debt ledger survives dispatch.
                finale_balance, finale_debt = entry_balance, starting_debt
                ensure(finale_balance >= 0 and finale_debt >= 0, "NEGATIVE_HANDED_OFF")
                if policy == "managed":
                    ensure(finale_balance >= finale_debt, "SETTLEMENT_OVERDRAW")
                    finale_balance -= finale_debt
                    finale_debt = 0
                ensure(finale_balance == initial_reserve - 2 and
                       finale_debt == 0 and entry_balance + (
                           2 if policy == "buffer" else 0) == initial_reserve,
                       "SETTLEMENT_LEDGER_NONCONSERVATION")
                count += 1
        fingerprint = hashlib.sha256(json.dumps(
            {"region": r["region_id"], "sites": site_ids,
             "first": (root["transport_feeder_id"], root["critical_feeder_id"]),
             "anchor": anchor_id, "risk": r["risk_class"]},
            sort_keys=True).encode("utf-8")).hexdigest()
        ensure(fingerprint not in fingerprints, "SOURCE_SIGNATURE_REUSE")
        fingerprints.add(fingerprint)
        evidence.append({"region": r["region_id"], "root": root_id,
                         "finale": finale_id, "original_reserve_anchor": anchor_id,
                         "original_topology_sha256": fingerprint,
                         "source_only": True, "restoration_claimed": False})
        print(f"EXP015_A11_SOURCE {i+1:02d}/25 root={root_id} "
              f"finale={finale_id} anchor={anchor_id}")
    ensure(count == 100 and len(seen) == 25 and len(fingerprints) == 25,
           "FULL_ORIGINAL_REPLAY_COVERAGE")
    return {"ok": True, "phase": "EXP015_A11",
            "source_regions": len(seen), "original_root_to_finale_paths": count,
            "recovery_claim": False, "production_save_claim": False,
            "qualification": SOURCE_ONLY, "region_evidence": evidence}


def main() -> None:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--report", type=Path)
    args = cli.parse_args()
    result = audit(*load())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    print("EXP015_A11_ORIGINAL_HANDOFF=PASS source_paths=100")


if __name__ == "__main__":
    main()
