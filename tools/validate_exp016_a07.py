#!/usr/bin/env python3
"""EXP016 A07 source-backed hazard protocols, station order and operation impact."""
from __future__ import annotations
import json
from pathlib import Path
from collections import Counter

ROOT=Path(__file__).resolve().parents[1]/"scenes/expeditions"
ORDER={"repairs":["A","C","B"],"switches":["B","A","C"],"both":["C","B","A"]}

def read(n):return json.loads((ROOT/n).read_text(encoding="utf-8"))

def qualify(a,e,c,b):
    if b.get("authority")!="EXP016_A07_ENVIRONMENTAL_OPERATION_ORDER" or len(b.get("entries",[]))!=200:
        raise ValueError("A07_HEADER")
    groups=Counter()
    for i,(lv,en,co,entry) in enumerate(zip(a["levels"],e["entries"],c["entries"],b["entries"])):
        blocks=en["hazard"]["blocks"]
        expected={"level_id":lv["id"],"location_id":lv["location_id"],"region_id":lv["region_id"],
                  "source_puzzle_identity":lv["puzzle_identity"],"source_task_ids":[t["id"] for t in lv["tasks"]],
                  "source_hazard_kind":en["hazard"]["kind"],"source_blocked_operations":blocks,
                  "source_risk_guard":co["risk_guard"],"survey_station":ORDER[blocks][0],
                  "isolate_station":ORDER[blocks][1],"clear_station":ORDER[blocks][2]}
        if any(entry.get(k)!=v for k,v in expected.items()):raise ValueError(f"A07_SOURCE_DRIFT:{i}")
        groups[blocks]+=1
    return {"status":"SOURCE_ONLY_HOLD","sites":200,"hazard_block_categories":dict(groups),
            "guarded_operations":600,"unsafe_resume":"DENY_UNTIL_SOURCE_CONTAINMENT"}

if __name__=="__main__":
    print("[EXP016 A07]",json.dumps(qualify(read("atlas.json"),read("bespoke_encounters.json"),
      read("site_contingencies_exp014_a02.json"),read("exp016_hazard_protocols_a07.json")),sort_keys=True))
