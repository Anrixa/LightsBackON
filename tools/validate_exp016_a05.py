#!/usr/bin/env python3
"""EXP016 A05 50-case investigation and authoritative signed completion audit."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "scenes/expeditions"

def load(name: str) -> dict:
    return json.loads((ROOT/name).read_text(encoding="utf-8"))

def qualify() -> dict:
    atlas = load("atlas.json")
    original = load("site_investigations_exp014_a08.json")
    cases = load("exp016_casework_a05.json")
    if cases.get("authority") != "EXP016_A05_AUTHENTICATED_CASEWORK" or cases.get("range") != [151,200]:
        raise ValueError("A05_SOURCE_HEADER")
    if len(cases["entries"]) != 50: raise ValueError("A05_COUNT")
    signatures=set()
    for i, case in enumerate(cases["entries"]):
        lv,prev=atlas["levels"][i+150],original["entries"][i+150]
        pins={"level_id":lv["id"],"location_id":lv["location_id"],"region_id":lv["region_id"],
              "source_puzzle_identity":lv["puzzle_identity"],"source_task_ids":[t["id"] for t in lv["tasks"]],
              "source_investigation_serial":prev["case_serial"],"source_risk":prev["source_risk"],
              "targets":prev["targets"],"recovery_target":prev["recovery_target"]}
        if any(case.get(key)!=value for key,value in pins.items()):
            raise ValueError("A05_SOURCE_DRIFT")
        if case.get("final_signoff_station") not in ("A","B","C"):
            raise ValueError("A05_SOURCE_SIGNOFF")
        structural=[]
        for mode in ("forensic","field"):
            route=case["routes"][mode]
            held={token:route["initial_tokens"].count(token) for token in route["initial_tokens"]}
            steps=route["steps"]
            seen=set()
            for s in steps:
                if s["id"] in seen or not set(s["requires"]).issubset(seen): raise ValueError("A05_DAG")
                for token in s["requires_tokens"]:
                    if held.get(token,0)<1: raise ValueError("A05_UNEARNED_EVIDENCE")
                for token in s["consumes_tokens"]:
                    if held.get(token,0)<1: raise ValueError("A05_DOUBLE_SPEND")
                    held[token]-=1
                for token in s["grants_tokens"]: held[token]=held.get(token,0)+1
                seen.add(s["id"])
                structural.append((mode,s["kind"],s["station"],tuple(s["requires"]),s["guard"],
                                   s["cost"],tuple(s["requires_tokens"]),tuple(s["grants_tokens"])))
            if sum(s["cost"] for s in steps)>route["initial_kits"]: raise ValueError("A05_KIT_BUDGET")
        signatures.add(tuple(structural))
    if len(signatures)!=50: raise ValueError("A05_MECHANICAL_CLONES")
    return {"status":"SOURCE_ONLY_HELD", "levels":50,"routes":100, "source_signed_cases":50,
            "distinct_mechanical_solutions":len(signatures)}

if __name__=="__main__":
    print("[EXP016 A05] "+json.dumps(qualify(),sort_keys=True))
