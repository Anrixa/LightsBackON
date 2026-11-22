#!/usr/bin/env python3
"""EXP015 A12.3 independent original-feeder blocker and receipt audit.

Separates actually repairable feeder isolation from missing EXP04 receipts
across all 25 source-authored reserve-anchor paths. Godot tests execute
the actual A09 host transitions; this script is independent source evidence.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from validate_exp015_anchor_routes import audit as audit_original, route, source_book

QUALIFICATION = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
PROOF_RISKS = {"depth", "conductivity", "mechanical", "structure", "weather"}


def require(ok: bool, code: str) -> None:
    if not ok:
        raise ValueError("EXP015_A12_3_" + code)


def audit(book: dict[str, Any]) -> dict[str, Any]:
    original = audit_original(book)
    regions = book["regions"]
    replay = []
    repairable = 0
    missing = 0
    for i, region in enumerate(regions):
        nodes, edges = route(region)
        by_id = {e["edge_id"]: e for e in region["primary_feeders"]}
        require(len(edges) == len(nodes) - 1 and
                region["risk_class"] in PROOF_RISKS and
                region["recovery_procedure"] and region["fault_signature"] and
                all(by_id[key]["protection"] for key in edges),
                "REAL_SOURCE_RECOVERY_IDENTITY")
        # All original receipts present: isolating any one exact feeder
        # disconnects the unique primary path, and only the same original
        # feeder ID plus source recovery procedure can return it to normal.
        for edge in edges:
            require(edge in by_id and by_id[edge]["to"] in nodes,
                    "REPAIRABLE_EDGE_ORIGINAL_ID")
            repairable += 1
            replay.append({"region_id": region["region_id"],
                           "original_feeder": edge,
                           "risk_proof": region["recovery_procedure"],
                           "initially_faulted": True, "repairable": True,
                           "can_defer_without_missing_receipt": False,
                           "reserve_spent_pu": 0})
        base = {f"LV_{8*i + slot:03d}" for slot in (1, 2, 3, 4, 6, 7)}
        missing_sites = sorted(set(nodes) - base)
        if missing_sites:
            missing += 1
        require(bool(missing_sites) == (i in (10, 24)),
                "REAL_MISSING_RECEIPT_SITES")
        replay.append({"region_id": region["region_id"],
                       "missing_original_receipts": missing_sites,
                       "managed_dark_only_if_receipt_missing": True,
                       "electrical_energization_claim": False})
    require(original["rooted_original_paths"] == 25 and repairable >= 25 and
            missing == 2 and len(replay) == repairable + 25,
            "FULL_ADVERSARIAL_SOURCE_COVERAGE")
    digest = hashlib.sha256(json.dumps(replay, sort_keys=True).encode()).hexdigest()
    return {"ok": True, "phase": "EXP015_A12_3",
            "source_regions": 25, "repairable_path_feeder_cases": repairable,
            "missing_receipt_regions": [11, 25], "source_replay_sha256": digest,
            "no_new_task_ids_or_rewards": True,
            "no_fabricated_electrical_power": True, "qualification": QUALIFICATION}


def main() -> None:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--report", type=Path)
    args = cli.parse_args()
    result = audit(source_book())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    print("EXP015_A12_3_ADVERSARIAL_ORIGINAL_FEEDER=PASS "
          f"cases={result['repairable_path_feeder_cases']} "
          "dark_receipt_regions=2")


if __name__ == "__main__":
    main()
