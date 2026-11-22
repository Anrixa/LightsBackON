#!/usr/bin/env python3
"""EXP016 A06: 200 true source-bound dual-condition fault evidence pairs."""
from __future__ import annotations
import json
from pathlib import Path
from collections import Counter

ROOT=Path(__file__).resolve().parents[1]/"scenes/expeditions"
def read(name):
    return json.loads((ROOT/name).read_text(encoding="utf-8"))

def qualify(atlas, faults, encounters, book):
    if book.get("authority")!="EXP016_A06_DUAL_SOURCE_FAULT_LAYERS" or len(book.get("entries",[]))!=200:
        raise ValueError("A06_BAD_SOURCE_HEADER")
    pairs=set()
    for i,(lv,fa,en,entry) in enumerate(zip(atlas["levels"],faults["entries"],encounters["entries"],book["entries"])):
        pins={"level_id":lv["id"],"location_id":lv["location_id"],"region_id":lv["region_id"],
              "source_puzzle_identity":lv["puzzle_identity"],"source_task_ids":[t["id"] for t in lv["tasks"]],
              "fault_scenario_key":fa["scenario_key"],"primary_fault_class":fa["fault_class"],
              "primary_signal":fa["signal_a"],"secondary_fault_class":"environmental_"+en["hazard"]["kind"],
              "secondary_signal":en["hazard"]["kind"]+"|"+en["hazard"]["blocks"],"source_hazard_kind":en["hazard"]["kind"]}
        if any(entry.get(k)!=v for k,v in pins.items()): raise ValueError(f"A06_SOURCE_DRIFT:{i+1}")
        pairs.add((entry["primary_fault_class"],entry["secondary_fault_class"]))
    return {"status":"SOURCE_ONLY_HOLD", "levels":200,"source_pairs":len(pairs),
            "diagnosis_paths":400,"risk_conditions":["electrical fault","environmental concurrent fault"]}

if __name__=="__main__":
    print("[EXP016 A06]",json.dumps(qualify(read("atlas.json"),read("fault_diagnostics.json"),
         read("bespoke_encounters.json"),read("exp016_fault_layers_a06.json")),sort_keys=True))
