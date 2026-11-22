#!/usr/bin/env python3
"""EXP016 A10 validate 25 original directed source regional cascades."""
from __future__ import annotations
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]/"scenes/expeditions"

def load(name):return json.loads((ROOT/name).read_text(encoding="utf-8"))
def validate(atlas,network,book):
    if book.get("authority")!="EXP016_A10_PROCESS_LOCAL_SOURCE_CASCADE" or len(book.get("regions",[]))!=25:
        raise ValueError("A10_SOURCE_HEADER")
    total=0
    for reg,source in zip(network["regions"],book["regions"]):
        sites=[x["site_id"] for x in reg["source_sites"]]
        edges=[{"id":e["edge_id"],"from":e["from"],"to":e["to"],"capacity_pu":e["capacity_pu"]} for e in reg["primary_feeders"]]
        pre={x:[] for x in sites}
        for e in edges:
            if e["from"] not in sites or e["to"] not in sites:raise ValueError("A10_FOREIGN_FEEDER")
            pre[e["to"]].append(e["from"])
        if (source.get("region_id")!=reg["region_id"] or source.get("site_ids")!=sites or
            source.get("root_source_id")!=reg["root_source_id"] or
            source.get("primary_feeder_edges")!=edges or
            source.get("source_predecessors")!=pre or
            source.get("initial_reserve_pu")!=reg["initial_reserve_pu"] or
            source.get("finale_site_id")!=sites[-1]):
            raise ValueError("A10_SOURCE_DRIFT")
        total+=len(sites)
    if total!=200:raise ValueError("A10_SITE_COUNT")
    return {"status":"SOURCE_ONLY_HOLD","regions":25,"sites":total,
        "owner_scoped_cross_location_pressure":True,"durability":"PROCESS_LOCAL_ONLY"}

if __name__=="__main__":
    print("[EXP016 A10]",json.dumps(validate(load("atlas.json"),
     load("regional_networks_exp014_a09.json"),load("exp016_cascades_a10.json")),sort_keys=True))
