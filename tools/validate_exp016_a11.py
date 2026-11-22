#!/usr/bin/env python3
"""EXP016 A11 pin original collectibles and forbids new economy or reward types."""
from __future__ import annotations
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]/"scenes/expeditions"

def load(n):return json.loads((ROOT/n).read_text(encoding="utf-8"))

def qualify(a,i,b):
    if b.get("authority")!="EXP016_A11_SOURCE_LORE_DISCOVERIES" or len(b.get("entries",[]))!=200:
        raise ValueError("A11_SOURCE_HEADER")
    for idx,(lv,inv,entry) in enumerate(zip(a["levels"],i["entries"],b["entries"])):
        found=lv["collectible"]
        pins={"level_id":lv["id"],"location_id":lv["location_id"],"region_id":lv["region_id"],
              "source_puzzle_identity":lv["puzzle_identity"],"source_task_id":lv["tasks"][3]["id"],
              "source_collectible_id":found["id"],"source_collectible_name":found["name"],
              "source_lore_set":found["set"],"source_effect":found["effect"],
              "source_stations":inv["targets"]}
        if any(entry.get(k)!=v for k,v in pins.items()):raise ValueError(f"A11_SOURCE_DRIFT:{idx+1}")
        if entry["source_effect"]!="LORE_ONLY_NO_POWER_OR_CREDITS" or [
            (x["action"],x["station"],x["requires"]) for x in entry["research_chain"]] != [
            ("case_discover_trace","A",""),("case_discover_crosscheck","B","faults_solved"),
            ("case_discover_authenticate","C","consequences_solved")]:
            raise ValueError("A11_INVALID_LORE_ECONOMY_OR_RESEARCH")
    return {"status":"SOURCE_ONLY_HOLD", "collectibles":200,"original_job_ids":200,
            "authenticated_research_steps":600,"new_reward_types":0,"new_credits":0}

if __name__=="__main__":
    print("[EXP016 A11]",json.dumps(qualify(load("atlas.json"),
      load("site_investigations_exp014_a08.json"),load("exp016_discoveries_a11.json")),sort_keys=True))
