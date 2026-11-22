#!/usr/bin/env python3
"""EXP016 A03: independent source-fault and 100-branch negative-case qualifier."""
from __future__ import annotations
import json
from pathlib import Path
from collections import Counter

ROOT = Path(__file__).resolve().parents[1] / "scenes/expeditions"


def qualify() -> dict:
    def load(name: str) -> dict:
        return json.loads((ROOT / name).read_text(encoding="utf-8"))
    atlas, inv, faults, book = (load(n) for n in ("atlas.json", "site_investigations_exp014_a08.json",
                                              "fault_diagnostics.json", "exp016_casework_a03.json"))
    if book["authority"] != "EXP016_A03_AUTHENTICATED_CASEWORK" or book["range"] != [51,100] or len(book["entries"]) != 50:
        raise ValueError("EXP016_A03_HEADER")
    signatures = set()
    for serial in range(51, 101):
        case = book["entries"][serial-51]
        source, inquiry, fault = atlas["levels"][serial-1], inv["entries"][serial-1], faults["entries"][serial-1]
        pins = {"level_id":source["id"],"location_id":source["location_id"],
                "region_id":source["region_id"],"source_puzzle_identity":source["puzzle_identity"],
                "source_task_ids":[x["id"] for x in source["tasks"]],
                "source_investigation_serial":inquiry["case_serial"],"source_risk":inquiry["source_risk"],
                "targets":inquiry["targets"],"recovery_target":inquiry["recovery_target"],
                "diagnosis":{"scenario_key":fault["scenario_key"],"fault_class":fault["fault_class"],
                             "signal_a":fault["signal_a"],"signal_b":fault["signal_b"]}}
        if any(case.get(k) != v for k,v in pins.items()):
            raise ValueError("EXP016_A03_FAULT_OR_SOURCE_DRIFT")
        edges = []
        for name in ("forensic","field"):
            seen=set()
            route=case["routes"][name]
            for s in route["steps"]:
                if s["id"] in seen or not set(s["requires"]).issubset(seen):
                    raise ValueError("EXP016_A03_NON_DAG")
                seen.add(s["id"])
                edges.append((name,s["kind"],s["station"],tuple(s["requires"]),s["guard"],s["cost"]))
            if sum(s["cost"] for s in route["steps"]) > route["initial_kits"]:
                raise ValueError("EXP016_A03_FINITE_BUDGET")
        signatures.add(tuple(edges))
    if len(signatures) != 50:
        raise ValueError("EXP016_A03_MECHANICAL_CLONES")
    return {"cases":50,"routes":100,"unique_mechanical_routes":len(signatures),
            "distinct_fault_classes":len(set(e["diagnosis"]["fault_class"] for e in book["entries"])),
            "status":"SOURCE_ONLY_PHYSICAL_AND_RELEASE_HOLD"}


if __name__ == "__main__":
    print("[EXP016 A03] "+json.dumps(qualify(),sort_keys=True))
