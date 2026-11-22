#!/usr/bin/env python3
"""EXP016 A04: source identity plus single-use host evidence-token conservation."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "scenes/expeditions"


def load(name):
    return json.loads((ROOT / name).read_text(encoding="utf-8"))


def qualify():
    atlas, inv, casebook = load("atlas.json"), load("site_investigations_exp014_a08.json"), load("exp016_casework_a04.json")
    if casebook["range"] != [101,150] or casebook["authority"] != "EXP016_A04_AUTHENTICATED_CASEWORK":
        raise ValueError("A04_HEADER")
    signatures=set()
    for serial in range(101,151):
        case=casebook["entries"][serial-101]
        source,previous=atlas["levels"][serial-1],inv["entries"][serial-1]
        expected={"level_id":source["id"],"location_id":source["location_id"],"region_id":source["region_id"],
                  "source_puzzle_identity":source["puzzle_identity"],"source_task_ids":[t["id"] for t in source["tasks"]],
                  "source_investigation_serial":previous["case_serial"],"source_risk":previous["source_risk"],
                  "targets":previous["targets"],"recovery_target":previous["recovery_target"]}
        if any(case.get(k)!=v for k,v in expected.items()):
            raise ValueError("A04_SOURCE_DRIFT")
        signature=[]
        for route in ("forensic","field"):
            spec=case["routes"][route]
            held={token:spec["initial_tokens"].count(token) for token in set(spec["initial_tokens"])}
            seen=set()
            for step in spec["steps"]:
                if step["id"] in seen or not set(step["requires"]).issubset(seen):
                    raise ValueError("A04_DAG")
                for token in step["requires_tokens"]:
                    if held.get(token,0)<1:
                        raise ValueError("A04_UNEARNED_TOKEN")
                for token in step["consumes_tokens"]:
                    if held.get(token,0)<1:
                        raise ValueError("A04_DOUBLE_SPEND")
                    held[token]-=1
                for token in step["grants_tokens"]:
                    held[token]=held.get(token,0)+1
                seen.add(step["id"])
                signature.append((route,step["kind"],step["station"],tuple(step["requires"]),step["guard"],
                                  step["cost"],tuple(step["requires_tokens"]),tuple(step["grants_tokens"])))
            if sum(s["cost"] for s in spec["steps"])>spec["initial_kits"]:
                raise ValueError("A04_KIT_BUDGET")
        signatures.add(tuple(signature))
    if len(casebook["entries"]) != 50 or len(signatures)!=50:
        raise ValueError("A04_MECHANICAL_CLONE_OR_COUNT")
    return {"status":"SOURCE_ONLY_HOLD","levels":50,"routes":100,
            "distinct_host_evidence_graphs":len(signatures),"evidence_double_spends":0}


if __name__ == "__main__":
    print("[EXP016 A04] "+json.dumps(qualify(),sort_keys=True))
