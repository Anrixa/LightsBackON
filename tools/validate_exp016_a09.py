#!/usr/bin/env python3
"""EXP016 A09 source-policy and branch consequence oracle."""
from __future__ import annotations
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]/"scenes/expeditions"
def load(n):return json.loads((ROOT/n).read_text(encoding="utf-8"))

def qualify(atlas,cont,book):
    if book.get("authority")!="EXP016_A09_NONLINEAR_SOURCE_POLICIES" or len(book.get("entries",[]))!=200:
        raise ValueError("A09_HEADER")
    for i,(lv,prior,case) in enumerate(zip(atlas["levels"],cont["entries"],book["entries"])):
        pins={"level_id":lv["id"],"location_id":lv["location_id"],"region_id":lv["region_id"],
              "source_puzzle_identity":lv["puzzle_identity"],"source_task_ids":[t["id"] for t in lv["tasks"]],
              "original_priority_actions":prior["source_route_actions"]["priority"],
              "original_resilience_actions":prior["source_route_actions"]["resilience"],
              "original_guard":prior["risk_guard"]}
        if any(case.get(k)!=v for k,v in pins.items()):raise ValueError(f"A09_SOURCE_DRIFT:{i+1}")
        opts=case["options"]
        if opts["priority"]["route"]==opts["resilience"]["route"] or not opts["resilience"]["assurance_check"] or not opts["priority"]["service_debt"]>opts["resilience"]["service_debt"]:
            raise ValueError("A09_COSMETIC_BRANCH")
    return {"status":"SOURCE_ONLY_HOLD","levels":200,"mechanically_distinct_policy_choices":400,
            "priority_debt_cases":200,"resilience_extra_authentic_checks":200}

if __name__=="__main__":
    print("[EXP016 A09]",json.dumps(qualify(load("atlas.json"),
      load("site_contingencies_exp014_a02.json"),load("exp016_policies_a09.json")),sort_keys=True))
