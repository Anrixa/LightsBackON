#!/usr/bin/env python3
"""EXP015 A07 — independent 100 ORIGINAL alternate-route risk/feeder oracle.

The network's original feeder/tie topology, true restored-receipt supply and
finite reserve are authoritative. The alternate site itself is NOT restored
by any of these headless tests.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

if __package__:
    from .qualify_exp015_region_replay import audit as audit_a06, load as load_a06
    from .validate_exp015_finales import feeder_tree
else:
    from qualify_exp015_region_replay import audit as audit_a06, load as load_a06
    from validate_exp015_finales import feeder_tree

ROOT = Path(__file__).resolve().parents[1]
BOOK_PATH = ROOT / "scenes/expeditions/region_alt_routes_exp015_a07.json"
SOURCE_PATH = ROOT / "scenes/expeditions/regional_networks_exp014_a09.json"
HOLD = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
AUTHORITY = "EXP015_A07_ORIGINAL_ALTERNATE_ROUTE_EMERGENCIES"
ROLES = ("first_route_a", "first_route_b", "second_route_a", "second_route_b")
SLOTS = (1, 2, 4, 5)
RISKS: dict[str, tuple[str, int]] = {
    "depth": ("trenched_feeder_dewatering", 2),
    "conductivity": ("arc_free_critical_test", 4),
    "mechanical": ("interlock_return_proof", 2),
    "structure": ("shored_feeder_clearance", 3),
    "weather": ("span_exposure_recheck", 3),
}


def require(ok: bool, code: str) -> None:
    if not ok:
        raise ValueError("EXP015_A07_" + code)


def load() -> tuple[dict, dict]:
    return (json.loads(SOURCE_PATH.read_text(encoding="utf-8")),
            json.loads(BOOK_PATH.read_text(encoding="utf-8")))


def upstream_energized(region: dict, restored: set[str]) -> set[str]:
    alive = {region["root_source_id"]} if region["root_source_id"] in restored else set()
    for _ in range(8):
        for feeder in region["primary_feeders"]:
            if feeder["from"] in alive and feeder["to"] in restored:
                alive.add(feeder["to"])
    return alive


def audit(networks: dict, book: dict) -> dict[str, Any]:
    # The earlier source chain is a required separate gate, not a promotion.
    # It runs under tools/run_tests.sh as part of the inherited baseline.
    require(book.get("schema_version") == 1 and
            book.get("authority") == AUTHORITY and
            book.get("predecessor") == "EXP015_A06" and
            book.get("qualification") == HOLD and
            book.get("legacy_campaign_contracts_unchanged") is True and
            book.get("original_count") == 100 and
            isinstance(book.get("entries"), list) and
            len(book["entries"]) == 100 and
            len(networks.get("regions", [])) == 25, "SOURCE_AUTHORITY")
    seen: set[str] = set()
    signatures: set[str] = set()
    role_counts = {role: 0 for role in ROLES}
    mechanics = {"first_route_a_rapid_eligible": 0,
                 "first_route_b_upstream_priority_ready": 0,
                 "second_route_a_original_buffer_possible": 0,
                 "second_route_b_original_tie_a_ready": 0,
                 "second_route_b_original_tie_b_ready": 0}
    evidence = []
    for index, region in enumerate(networks["regions"]):
        sites, parents = feeder_tree(region)
        signature = (
            parents, sites.index(region["critical_service_site"]),
            sites.index(region["reserve_anchor_site"]),
            tuple((sites.index(t["from"]), sites.index(t["to"]))
                  for t in region["standby_ties"]),
            region["risk_class"], region["initial_reserve_pu"],
        )
        digest = hashlib.sha256(repr(signature).encode("utf-8")).hexdigest()
        require(digest not in signatures, "RENAMED_NETWORK_DUPLICATE")
        signatures.add(digest)
        roles = []
        for j, slot in enumerate(SLOTS):
            item = book["entries"][4 * index + j]
            original = region["source_sites"][slot]
            site = original["site_id"]
            role = original["campaign_role"]
            feeder = next((f for f in region["primary_feeders"]
                           if f["to"] == site), None)
            ties = [t for t in region["standby_ties"] if t["to"] == site]
            require(feeder is not None and role in ROLES and
                    len(ties) == (1 if role == "second_route_b" else 0),
                    "ORIGINAL_NETWORK_ROUTE")
            tie = ties[0] if ties else None
            risk = region["risk_class"]
            require(risk in RISKS and site not in seen and
                    item.get("route_site_id") == site and
                    item.get("region_id") == region["region_id"] and
                    item.get("location_id") == original["location_id"] and
                    item.get("worksite_family") == original["worksite_family"] and
                    item.get("campaign_role") == role and
                    item.get("task_ids") == original["source_task_ids"] and
                    item.get("normal_feeder_id") == feeder["edge_id"] and
                    item.get("upstream_site_id") == feeder["from"] and
                    item.get("capacity_pu") == feeder["capacity_pu"] and
                    item.get("original_protection") == feeder["protection"] and
                    item.get("original_fault_signature") == region["fault_signature"] and
                    item.get("original_recovery_procedure") ==
                    region["recovery_procedure"] and
                    item.get("risk_class") == risk and
                    item.get("risk_containment_protocol") == RISKS[risk][0] and
                    type(item.get("managed_outage_pressure_pu")) is int and
                    item["managed_outage_pressure_pu"] == RISKS[risk][1] and
                    item.get("standby_tie_id") == (tie["edge_id"] if tie else "") and
                    item.get("standby_source_site") == (tie["from"] if tie else "") and
                    item.get("initial_reserve_pu") == region["initial_reserve_pu"] and
                    item.get("qualification") == HOLD, "ORIGINAL_ALT_ASSET_PROOF")
            seen.add(site)
            roles.append(role)
            role_counts[role] += 1
            if role == "first_route_a":
                mechanics["first_route_a_rapid_eligible"] += int(
                    feeder["capacity_pu"] >= 16)
            if role == "first_route_b":
                require(site == region["critical_service_site"],
                        "ORIGINAL_CRITICAL_ROLE")
                mechanics["first_route_b_upstream_priority_ready"] += int(
                    feeder["from"] == region["root_source_id"])
            if role == "second_route_a":
                mechanics["second_route_a_original_buffer_possible"] += int(
                    region["initial_reserve_pu"] >= 2)
            if role == "second_route_b":
                for route, field in (
                    ("a", "second_route_b_original_tie_a_ready"),
                    ("b", "second_route_b_original_tie_b_ready")
                ):
                    receipts = {
                        sites[0], sites[1 if route == "a" else 2], sites[3]
                    }
                    live = upstream_energized(region, receipts)
                    require(site not in receipts and
                            region["initial_reserve_pu"] >= 2,
                            "NEVER_FAKE_RESTORED_ROUTE")
                    mechanics[field] += int(tie["from"] in live)
        require(tuple(roles) == ROLES, "ORIGINAL_ROUTE_ROLE_ORDER")
        evidence.append({"region_id": region["region_id"],
                         "original_route_sites": [sites[x] for x in SLOTS],
                         "original_network_sha256": digest})
        print(f"EXP015_A07_SOURCE {index+1:02}/25 {region['region_id']} "
              f"roles=4 original_route_sites={','.join(sites[x] for x in SLOTS)}")
    require(len(seen) == 100 and len(signatures) == 25 and
            all(v == 25 for v in role_counts.values()), "SOURCE_COVERAGE")
    require(mechanics == {
        "first_route_a_rapid_eligible": 20,
        "first_route_b_upstream_priority_ready": 25,
        "second_route_a_original_buffer_possible": 25,
        "second_route_b_original_tie_a_ready": 12,
        "second_route_b_original_tie_b_ready": 14,
    }, "SOURCE_ROUTE_FEASIBILITY_DRIFT")
    return {"ok": True, "phase": "EXP015_A07",
            "original_route_sites": len(seen), "regions": 25,
            "unique_original_networks": len(signatures),
            "role_counts": role_counts, "risk_classes": len(RISKS),
            "branch_route_scenarios": 125,
            "source_derived_mechanics": mechanics,
            "qualifier": HOLD, "legacy_level_task_reward_save_mutations": False,
            "hardware_steam_2peer_playability_release_certified": False,
            "evidence": evidence}


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--report", type=Path)
    args = p.parse_args()
    outcome = audit(*load())
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(outcome, indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    print("EXP015_A07_SOURCE_PASS " + json.dumps({
        k: v for k, v in outcome.items() if k != "evidence"
    }, sort_keys=True))


if __name__ == "__main__":
    main()
