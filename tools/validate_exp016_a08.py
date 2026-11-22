#!/usr/bin/env python3
"""EXP016 A08 independent equipment admission and source-spare audit."""
from __future__ import annotations
import json
from pathlib import Path
from collections import Counter

ROOT=Path(__file__).resolve().parents[1]/"scenes/expeditions"
TOOLS=["meter","screwdriver","puller","cutter","crimper"]
MAPPING={"trace":"meter","isolate":"screwdriver","crosscheck":"meter","tag":"puller","compare":"meter",
         "meter":"meter","repair":"crimper","reconcile":"cutter","attest":"meter","stabilize":"screwdriver"}

def read(name):return json.loads((ROOT/name).read_text(encoding="utf-8"))

def audit(atlas,works,book):
    if book.get("authority")!="EXP016_A08_AUTHENTICATED_EQUIPMENT_ALLOCATION" or len(book.get("entries",[]))!=200:
        raise ValueError("EXP016_A08_SOURCE_HEADER")
    budgets=Counter()
    for i,(lv,work,gear) in enumerate(zip(atlas["levels"],works["entries"],book["entries"])):
        expected={"level_id":lv["id"],"location_id":lv["location_id"],"region_id":lv["region_id"],
                  "source_puzzle_identity":lv["puzzle_identity"],"source_task_ids":[t["id"] for t in lv["tasks"]],
                  "source_worksite_encounter_key":work["encounter_key"],"reserve_cells":work["cell_budget"],
                  "authorized_tools":TOOLS,"required_tools":MAPPING,"charged_operations":["repair"]}
        if any(gear.get(k)!=v for k,v in expected.items()):
            raise ValueError(f"EXP016_A08_SOURCE_DRIFT:{i+1}")
        budgets[gear["reserve_cells"]]+=1
    for phase in ("a02","a03","a04","a05"):
        for case in read(f"exp016_casework_{phase}.json")["entries"]:
            serial=int(case["level_id"].split("_")[1])
            reserve=book["entries"][serial-1]["reserve_cells"]
            for name in ("forensic","field"):
                costed=sum(1 for s in case["routes"][name]["steps"] if s["kind"]=="repair" and s["cost"]>0)
                if costed>reserve:raise ValueError(f"EXP016_A08_UNSOLVABLE_SPARES:{serial}")
    return {"status":"SOURCE_ONLY_HOLD","source_bound_tools":len(TOOLS),"cases":200,
            "routes_qualified":400,"reserve_distribution":dict(budgets)}

if __name__=="__main__":print("[EXP016 A08]",json.dumps(audit(read("atlas.json"),
    read("field_work_orders.json"),read("exp016_equipment_a08.json")),sort_keys=True))
