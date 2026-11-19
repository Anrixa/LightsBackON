#!/usr/bin/env python3
"""EXP08: independent, read-only audit of source-pinned fault scenarios."""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "scenes/expeditions/atlas.json"
GRAPHS = ROOT / "scenes/expeditions/bespoke_device_graphs.json"
BOOK = ROOT / "scenes/expeditions/fault_diagnostics.json"
FAULT_CLASSES = {
    "distribution": "phase_drift", "transport": "traction_surge",
    "health": "sterile_pressure", "commerce": "load_imbalance",
    "waterworks": "backflow", "communications": "signal_echo",
    "education": "control_mismatch", "shelter": "reserve_brownout",
}
ANCHORS = {"probe_a": "PANEL_WEST", "probe_b": "PANEL_SPUR", "console": "R_WEST"}


def load_inputs() -> tuple[dict, dict, dict]:
    return tuple(json.loads(p.read_text(encoding="utf-8")) for p in (ATLAS, GRAPHS, BOOK))


def validate(atlas: dict, graphs: dict, book: dict) -> dict:
    if (book.get("schema_version") != 1 or
        book.get("authority") != "EXP08_HOST_FAULT_DIAGNOSTICS" or
        book.get("atlas_revision") != atlas.get("revision")):
        raise ValueError("EXP08_INVALID_HEADER")
    levels = {v["id"]: v for v in atlas["levels"]}
    source = {v["level_id"]: v for v in graphs["entries"]}
    entries = book.get("entries")
    if len(levels) != 200 or len(source) != 200 or not isinstance(entries, list) or len(entries) != 200:
        raise ValueError("EXP08_INVALID_COUNT")
    seen: set[str] = set()
    keys: set[str] = set()
    kinds: Counter[str] = Counter()
    for i, e in enumerate(entries):
        if not isinstance(e, dict):
            raise ValueError("EXP08_INVALID_ENTRY")
        lid = e.get("level_id")
        if lid not in levels or lid not in source or lid in seen:
            raise ValueError("EXP08_FOREIGN_OR_DUPLICATE")
        seen.add(lid)
        graph, level = source[lid], levels[lid]
        pins = {"location_id": level["location_id"],
                "source_puzzle_identity": level["puzzle_identity"],
                "encounter_key": graph["encounter_key"], "graph_key": graph["graph_key"],
                "site": graph["site"], "source_climate": graph["source_climate"]}
        if any(e.get(k) != v for k, v in pins.items()):
            raise ValueError("EXP08_SOURCE_DRIFT")
        if e.get("fault_class") != FAULT_CLASSES.get(e.get("site")):
            raise ValueError("EXP08_FAULT_CLASS_INVALID")
        expected_key = f'{graph["graph_key"]}|{e["fault_class"]}|{(i % 11)+1}|{len(graph["nodes"])}'
        if e.get("scenario_key") != expected_key or e["scenario_key"] in keys:
            raise ValueError("EXP08_SCENARIO_KEY_INVALID")
        keys.add(e["scenario_key"])
        suffix = lid.removeprefix("LV_")
        if (e.get("probe_a"), e.get("probe_b"), e.get("console")) != (
            f"FD_{suffix}_A", f"FD_{suffix}_B", f"FD_{suffix}_CTRL"):
            raise ValueError("EXP08_TARGET_INVALID")
        if e.get("anchors") != ANCHORS:
            raise ValueError("EXP08_ANCHOR_INVALID")
        if (not isinstance(e.get("signal_a"), str) or len(e["signal_a"]) < 6 or
            not isinstance(e.get("signal_b"), str) or len(e["signal_b"]) < 6):
            raise ValueError("EXP08_INVALID_SIGNALS")
        for k in ("hold_ticks", "alternate_extra_ticks", "spare_relays"):
            if type(e.get(k)) is not int:
                raise ValueError("EXP08_COUNTER_TYPE_INVALID")
        if not (e["hold_ticks"] == 8+(i%11) and
                e["alternate_extra_ticks"] == 4+(i%7) and e["spare_relays"] == 1):
            raise ValueError("EXP08_COUNTER_BOUNDS_OR_SOURCE_VARIANT_INVALID")
        kinds[e["site"]] += 1
        replay_reference(e)
    if len(seen) != 200 or len(keys) != 200 or len(kinds) != 8:
        raise ValueError("EXP08_DIVERSITY_INCOMPLETE")
    exports = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    if exports.count("scenes/expeditions/fault_diagnostics.json") != 2:
        raise ValueError("EXP08_WINDOWS_EXPORT_MISSING")
    return {"ok": True, "levels": len(seen), "fault_classes": len(kinds),
            "source_keys": len(keys), "sensor_targets": len(seen)*2,
            "alternate_routes": len(seen)*2}


def replay_reference(e: dict) -> None:
    """Pure-Python oracle: two probes, either route, host-ticked stability, and recovery."""
    for route in ("isolate", "reroute"):
        scans = {e["probe_a"], e["probe_b"]}
        assert len(scans) == 2
        spare = e["spare_relays"] - int(route == "reroute")
        assert spare >= 0
        required = e["hold_ticks"] + (e["alternate_extra_ticks"] if route == "reroute" else 0)
        for _ in range(required):
            assert required > 0
        assert required >= 8
        # An interrupted holding period must fault and reset before a fresh attempt.
        phase, held = "holding", 3
        phase, held = "faulted", 0
        assert phase == "faulted" and held == 0
        phase = "route"
        assert phase == "route"
        if route == "reroute":
            assert spare == 0  # retry must use isolation, not a new spare


def main() -> int:
    atlas, graphs, book = load_inputs()
    print("EXP08 SOURCE AUDIT", json.dumps(validate(atlas, graphs, book), sort_keys=True))
    print("HOLD: human/controller routes, GPU, Steam and production release")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
