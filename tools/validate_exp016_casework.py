#!/usr/bin/env python3
"""EXP016 A02: independent source-pinned and genuinely structural casework audit."""
from __future__ import annotations
from collections import Counter
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _load(path: str) -> dict:
    return json.loads((ROOT / "scenes/expeditions" / path).read_text(encoding="utf-8"))


def signature(entry: dict) -> str:
    return json.dumps([
        (mode, [(s["kind"], s["station"], s["requires"], s["guard"], s["cost"])
                for s in entry["routes"][mode]["steps"]])
        for mode in ("forensic", "field")
    ], sort_keys=True)


def audit(atlas: dict, investigation: dict, cases: dict) -> dict:
    if cases.get("authority") != "EXP016_A02_AUTHENTICATED_CASEWORK" or len(cases.get("entries", [])) != 50:
        raise ValueError("EXP016_A02_BOOK_HEADER")
    signatures: list[str] = []
    for i, case in enumerate(cases["entries"]):
        level, source = atlas["levels"][i], investigation["entries"][i]
        pins = {
            "level_id": level["id"], "location_id": level["location_id"],
            "region_id": level["region_id"], "source_puzzle_identity": level["puzzle_identity"],
            "source_task_ids": [x["id"] for x in level["tasks"]],
            "source_investigation_serial": source["case_serial"],
            "source_risk": source["source_risk"],
            "targets": source["targets"], "recovery_target": source["recovery_target"]
        }
        if any(case.get(k) != v for k, v in pins.items()):
            raise ValueError("EXP016_A02_SOURCE_DRIFT")
        for mode in ("forensic", "field"):
            steps = case["routes"][mode]["steps"]
            seen: set[str] = set()
            total = 0
            if len(steps) < 5:
                raise ValueError("EXP016_A02_INCOMPLETE")
            for step in steps:
                if step["id"] in seen or not set(step["requires"]).issubset(seen):
                    raise ValueError("EXP016_A02_DAG")
                if step["guard"] not in ("faults_solved","balancing_solved","logistics_solved","consequences_solved") or step["station"] not in ("A","B","C"):
                    raise ValueError("EXP016_A02_GUARD_OR_STATION")
                seen.add(step["id"])
                total += step["cost"]
            if total > case["routes"][mode]["initial_kits"]:
                raise ValueError("EXP016_A02_KIT_BUDGET")
        signatures.append(signature(case))
    unique = len(set(signatures))
    if unique != 50:
        raise ValueError(f"EXP016_A02_MECHANICAL_CLONES: {50-unique}")
    return {"status": "SOURCE_PASS_RELEASE_HOLD", "cases": 50, "routes": 100,
            "distinct_noncosmetic_signatures": unique,
            "operations": sum(sum(len(v["steps"]) for v in e["routes"].values())
                              for e in cases["entries"]),
            "owner_holds": ["controller", "hardware", "network", "production save", "economy", "release"]}


if __name__ == "__main__":
    import sys
    try:
        result = audit(_load("atlas.json"),
                       _load("site_investigations_exp014_a08.json"),
                       _load("exp016_casework_a02.json"))
        print("[EXP016 A02][PASS SOURCE ONLY]", json.dumps(result, sort_keys=True))
    except (ValueError, KeyError, TypeError) as exc:
        print("[EXP016 A02][FAIL]", exc)
        sys.exit(1)
