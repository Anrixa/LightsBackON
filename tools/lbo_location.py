#!/usr/bin/env python3
"""RB02 location format: loader and validator for content/locations/<location>/ (ADR-019 point 1).

A location is the authored place a contract or challenge is played on. Its manifest (location.json) names three files:
the layout (kit layout on the 4 m grid, routes, props, markers and zones; rules), the dressing and the look (presentation
only). The manifest itself holds the physical grid (nodes at sockets, edges), landmarks, crew spawns and the opening
shot, the extraction zone and the stage-audit backdrop. Format: docs/design/RB02-location-format.md.

scripts/world/location_data.gd is the GDScript twin. Both return diagnostics {code, message, ids} with the same codes;
tests/data/locations/cases.json pins the codes for a set of broken copies of Alder Street and both test suites run it.
Integer-only numbers are checked for every content file by tools/validate_content.py (ADR-003), not here.

    python tools/lbo_location.py            # validate every location and the contracts and challenges pinned to it
Exit 0 = every location valid.
"""
from __future__ import annotations

import copy
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
LOCATIONS = ROOT / "content" / "locations"
KIT_PIECES = ROOT / "content" / "world" / "kit_pieces.json"
KIT_DIMENSIONS = ROOT / "content" / "world" / "kit_dimensions.json"
SCHEMA = 1
ID_RE = re.compile(r"^[A-Z0-9_]+$")
FILE_KEYS = ("layout", "dressing", "look")
NODE_KINDS = ("source", "junction", "consumer")
SOCKET_KINDS = ("building", "prop", "marker", "feed")
MARKER_KINDS = ("spawn", "viewpoint", "anchor", "panel", "switch", "consumer")
LANDMARK_ROLES = ("hero", "secondary", "base")
FACES = ("south", "north", "west", "east")
CREW_SPAWNS = 4
YAW_LIMIT_DEG = 180
PITCH_LIMIT_DEG = 89


def diag(code: str, message: str, ids: list[str]) -> dict:
    return {"code": code, "message": message, "ids": sorted(ids)}


def res_path(res: str) -> Path:
    return ROOT / res.removeprefix("res://")


def _json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def load(location_dir: Path) -> dict:
    """Bundle {dir, manifest, layout, dressing, look}; a missing or unreadable file loads as {} (validate reports it)."""
    out: dict = {"dir": location_dir.name, "manifest": {}, "layout": {}, "dressing": {}, "look": {}}
    try:
        out["manifest"] = _json(location_dir / "location.json")
    except (OSError, ValueError):
        return out
    files = out["manifest"].get("files", {})
    for key in FILE_KEYS:
        name = files.get(key) if isinstance(files, dict) else None
        if isinstance(name, str) and "/" not in name and "\\" not in name:
            try:
                out[key] = _json(location_dir / name)
            except (OSError, ValueError):
                pass
    return out


def all_locations() -> dict[str, dict]:
    """location_id -> bundle for every content/locations/<dir>/location.json."""
    out: dict[str, dict] = {}
    for d in sorted(p for p in LOCATIONS.iterdir() if (p / "location.json").is_file()):
        b = load(d)
        out[str(b["manifest"].get("location_id", d.name))] = b
    return out


def kit_ids() -> list[str]:
    return [p["id"] for p in _json(KIT_PIECES)["pieces"]]


def dimensions() -> dict:
    return _json(KIT_DIMENSIONS)


def merged_look(bundle: dict) -> dict:
    """The look dictionary the street code reads: the shared profile with the location's environment overrides and
    building palette ("buildings"). Mirrors LocationData.look()."""
    loc = bundle["look"]
    look = copy.deepcopy(_json(res_path(loc["profile"])))
    look["environment"].update(copy.deepcopy(loc.get("environment", {})))
    look["buildings"] = copy.deepcopy(loc["palette"])
    return look


def merged_dressing(bundle: dict) -> dict:
    """The dressing dictionary StreetDressing reads: the location dressing plus the lamps from its look."""
    dress = copy.deepcopy(bundle["dressing"])
    dress["lamps"] = copy.deepcopy(bundle["look"].get("lamps", []))
    return dress


# --- validation ---------------------------------------------------------------------------------------------------

def _ints(v: Any, n: int) -> list[int] | None:
    if isinstance(v, list) and len(v) == n and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in v):
        return [int(x) for x in v]
    return None


def _records(v: Any) -> list[dict]:
    return [r for r in v if isinstance(r, dict)] if isinstance(v, list) else []


def _index(layout: dict) -> dict[str, dict[str, dict]]:
    return {k: {str(r.get("id")): r for r in _records(layout.get(k))}
            for k in ("buildings", "routes", "props", "markers", "zones", "kit_placements")}


def _ref(ref: Any, allowed: tuple[str, ...]) -> tuple[str, str] | None:
    """A reference is a one-key object {kind: id}; returns (kind, id) or None."""
    if isinstance(ref, dict) and len(ref) == 1:
        kind, rid = next(iter(ref.items()))
        if kind in allowed and isinstance(rid, str) and rid:
            return kind, rid
    return None


def _resolves(kind: str, rid: str, idx: dict, dressing: dict) -> bool:
    if kind == "feed":
        return isinstance(dressing.get(rid), dict)
    return rid in idx[kind + "s"]


def _validate_layout(layout: dict, kit: list[str], dims: dict, errs: list[dict]) -> None:
    module, step = int(dims["module_cm"]), int(dims["placement_increment_cm"])
    env = _ints(layout.get("envelope_cm"), 2)
    if env is None or min(env) <= 0:
        errs.append(diag("BAD_LAYOUT", "envelope_cm must be two positive ints", []))
        return
    seen: set[str] = set()
    for key in ("buildings", "routes", "props", "markers", "zones", "kit_placements"):
        if not isinstance(layout.get(key), list):
            errs.append(diag("BAD_LAYOUT", f"layout needs a {key} list", []))
        for r in _records(layout.get(key)):
            rid = r.get("id")
            if not (isinstance(rid, str) and ID_RE.match(rid)):
                errs.append(diag("INVALID_ID", f"{key}: every record needs an id matching ^[A-Z0-9_]+$", []))
                continue
            if rid in seen:
                errs.append(diag("DUPLICATE_ID", f"layout id {rid} is used twice", [rid]))
            seen.add(rid)

    def inside(rid: str, x: int, z: int, w: int, d: int) -> None:
        if x < 0 or z < 0 or x + w > env[0] or z + d > env[1]:
            errs.append(diag("OUTSIDE_ENVELOPE", f"{rid} leaves the {env[0]} x {env[1]} cm envelope", [rid]))

    def on_step(rid: str, values: list[int]) -> None:
        if any(v % step for v in values):
            errs.append(diag("OFF_GRID", f"{rid} is off the {step} cm placement grid", [rid]))

    for b in _records(layout.get("buildings")):
        rid = str(b.get("id"))
        lo, size = _ints(b.get("min_cm"), 2), _ints(b.get("size_cm"), 2)
        if lo is None or size is None or min(size) <= 0:
            errs.append(diag("BAD_LAYOUT", f"{rid} needs min_cm and size_cm", [rid]))
            continue
        if any(s % module for s in size):
            errs.append(diag("OFF_GRID", f"{rid} size is not on the {module} cm module", [rid]))
        on_step(rid, lo)
        inside(rid, lo[0], lo[1], size[0], size[1])
        for storey in ("ground", "upper"):
            faces = b.get(storey, {})
            if not isinstance(faces, dict):
                errs.append(diag("BAD_FACE", f"{rid} {storey} must map faces to piece lists", [rid]))
                continue
            for face, pieces in faces.items():
                want = size[0 if face in ("south", "north") else 1] // module
                if face not in FACES or not isinstance(pieces, list) or len(pieces) != want:
                    errs.append(diag("BAD_FACE", f"{rid} {storey} {face} needs one piece per module ({want})", [rid]))
                elif any(p not in kit for p in pieces):
                    errs.append(diag("UNKNOWN_PIECE", f"{rid} {storey} {face} names a piece the kit does not have", [rid]))
    for r in _records(layout.get("routes")):
        rid, lo, size = str(r.get("id")), _ints(r.get("min_cm"), 2), _ints(r.get("size_cm"), 2)
        if lo is None or size is None:
            errs.append(diag("BAD_LAYOUT", f"{rid} needs min_cm and size_cm", [rid]))
            continue
        on_step(rid, lo + size)
        inside(rid, lo[0], lo[1], size[0], size[1])
    for key in ("props", "zones"):
        for p in _records(layout.get(key)):
            rid, lo, size = str(p.get("id")), _ints(p.get("min_cm"), 3), _ints(p.get("size_cm"), 3)
            if lo is None or size is None:
                errs.append(diag("BAD_LAYOUT", f"{rid} needs 3D min_cm and size_cm", [rid]))
                continue
            if key == "props":  # zones are trigger volumes, not placed modules
                on_step(rid, [lo[0], lo[2], size[0], size[2]])
            inside(rid, lo[0], lo[2], size[0], size[2])
    for p in _records(layout.get("kit_placements")):
        rid, pos = str(p.get("id")), _ints(p.get("pos_cm"), 3)
        if pos is None:
            errs.append(diag("BAD_LAYOUT", f"{rid} needs pos_cm", [rid]))
            continue
        if p.get("piece") not in kit:
            errs.append(diag("UNKNOWN_PIECE", f"{rid} names a piece the kit does not have", [rid]))
        on_step(rid, pos)
    for m in _records(layout.get("markers")):
        rid, pos = str(m.get("id")), _ints(m.get("pos_cm"), 3)
        if pos is None or m.get("kind") not in MARKER_KINDS:
            errs.append(diag("BAD_MARKER", f"{rid} needs pos_cm and a kind in {MARKER_KINDS}", [rid]))
            continue
        inside(rid, pos[0], pos[2], 0, 0)


def _validate_grid(grid: Any, idx: dict, dressing: dict, errs: list[dict]) -> None:
    if not isinstance(grid, dict) or not isinstance(grid.get("nodes"), list) or not isinstance(grid.get("edges"), list):
        errs.append(diag("BAD_GRID", "grid needs nodes and edges lists", []))
        return
    kinds: dict[str, str] = {}
    for n in _records(grid["nodes"]):
        nid = n.get("id")
        if not (isinstance(nid, str) and ID_RE.match(nid)):
            errs.append(diag("INVALID_ID", "grid node ids must match ^[A-Z0-9_]+$", []))
            continue
        if nid in kinds:
            errs.append(diag("DUPLICATE_ID", f"grid node {nid} is listed twice", [nid]))
        if n.get("kind") not in NODE_KINDS:
            errs.append(diag("BAD_GRID", f"{nid} kind must be one of {NODE_KINDS}", [nid]))
        kinds[nid] = str(n.get("kind"))
        ref = _ref(n.get("socket"), SOCKET_KINDS)
        if ref is None:
            errs.append(diag("BAD_SOCKET", f"{nid} socket must be one of {SOCKET_KINDS}", [nid]))
        elif not _resolves(ref[0], ref[1], idx, dressing):
            errs.append(diag("UNKNOWN_REF", f"{nid} socket {ref[0]} {ref[1]} is not in the location", [nid]))
        elif ref[0] == "building" and not idx["buildings"][ref[1]].get("service", False):
            errs.append(diag("BAD_SOCKET", f"{nid} sits in {ref[1]}, which is not a service building", [nid]))
    edge_ids: set[str] = set()
    for e in _records(grid["edges"]):
        eid = e.get("id")
        if not (isinstance(eid, str) and ID_RE.match(eid)):
            errs.append(diag("INVALID_ID", "grid edge ids must match ^[A-Z0-9_]+$", []))
            continue
        if eid in edge_ids or eid in kinds:
            errs.append(diag("DUPLICATE_ID", f"grid edge {eid} is listed twice", [eid]))
        edge_ids.add(eid)
        a, b = e.get("from"), e.get("to")
        if a not in kinds or b not in kinds or a == b or kinds.get(b) == "source" or kinds.get(a) == "consumer":
            errs.append(diag("BAD_GRID", f"{eid} must run from a source or junction to a junction or consumer", [eid]))


def validate(bundle: dict, kit: list[str] | None = None, dims: dict | None = None) -> list[dict]:
    """Structural and referential checks; [] means the location can be built, dressed and audited."""
    kit = kit if kit is not None else kit_ids()
    dims = dims if dims is not None else dimensions()
    m = bundle["manifest"]
    errs: list[dict] = []
    if not isinstance(m, dict) or not m:
        return [diag("MISSING_FILE", "location.json is missing or unreadable", [])]
    if m.get("schema") != SCHEMA:
        errs.append(diag("BAD_SCHEMA", f"schema must be {SCHEMA}", []))
    for key in ("location_id", "district_id"):
        if not (isinstance(m.get(key), str) and ID_RE.match(m[key])):
            errs.append(diag("INVALID_ID", f"{key} must match ^[A-Z0-9_]+$", []))
    if not (isinstance(m.get("name_key"), str) and m["name_key"]):
        errs.append(diag("BAD_VALUE", "name_key must be a text key", []))
    scene = m.get("scene")
    if not (isinstance(scene, str) and scene.startswith("res://") and scene.endswith(".tscn")):
        errs.append(diag("BAD_VALUE", "scene must be a res:// .tscn path", []))
    for key in FILE_KEYS:
        if not bundle.get(key):
            errs.append(diag("MISSING_FILE", f"files.{key} is missing or unreadable", []))
    if errs and any(e["code"] == "MISSING_FILE" for e in errs):
        return errs
    look = bundle["look"]
    if not (isinstance(look.get("profile"), str) and res_path(look["profile"]).is_file()
            and isinstance(look.get("environment"), dict) and isinstance(look.get("palette"), dict)
            and isinstance(look.get("lamps"), list)):
        errs.append(diag("BAD_LOOK", "look needs a profile file, environment overrides, a palette and lamps", []))
    layout, dressing = bundle["layout"], bundle["dressing"]
    _validate_layout(layout, kit, dims, errs)
    idx = _index(layout)
    _validate_grid(m.get("grid"), idx, dressing, errs)

    landmarks = m.get("landmarks")
    heroes = 0
    for lm in _records(landmarks):
        ref = _ref(lm.get("ref"), ("building", "prop"))
        if ref is None or lm.get("role") not in LANDMARK_ROLES:
            errs.append(diag("BAD_LANDMARK", f"a landmark needs a building or prop ref and a role in {LANDMARK_ROLES}", []))
            continue
        if not _resolves(ref[0], ref[1], idx, dressing):
            errs.append(diag("UNKNOWN_REF", f"landmark {ref[0]} {ref[1]} is not in the layout", [ref[1]]))
        heroes += lm["role"] == "hero"
    if heroes != 1:
        errs.append(diag("BAD_LANDMARK", f"a location has exactly one hero landmark, not {heroes}", []))

    spawn = m.get("spawn") if isinstance(m.get("spawn"), dict) else {}
    spawns = spawn.get("markers")
    if not (isinstance(spawns, list) and len(spawns) == CREW_SPAWNS and len(set(map(str, spawns))) == CREW_SPAWNS
            and all(idx["markers"].get(str(s), {}).get("kind") == "spawn" for s in spawns)):
        errs.append(diag("BAD_SPAWN", f"spawn.markers must name {CREW_SPAWNS} distinct spawn markers", []))
        spawns = []
    shot = spawn.get("opening_shot") if isinstance(spawn.get("opening_shot"), dict) else {}
    yaw, pitch, near = shot.get("yaw_deg"), shot.get("pitch_deg"), shot.get("max_near_wall_percent")
    job = _ref(shot.get("first_job"), ("building", "prop", "marker"))
    if shot.get("from") not in spawns or not isinstance(yaw, int) or abs(yaw) > YAW_LIMIT_DEG \
            or not isinstance(pitch, int) or abs(pitch) > PITCH_LIMIT_DEG \
            or not isinstance(near, int) or not 0 <= near <= 100 or job is None:
        errs.append(diag("BAD_SPAWN", "opening_shot needs from (a spawn), yaw_deg, pitch_deg, first_job and max_near_wall_percent", []))
    elif not _resolves(job[0], job[1], idx, dressing):
        errs.append(diag("UNKNOWN_REF", f"opening_shot first_job {job[0]} {job[1]} is not in the layout", [job[1]]))

    ext = m.get("extraction")
    zone = ext.get("zone") if isinstance(ext, dict) else None
    if not isinstance(zone, str) or zone not in idx["zones"]:
        errs.append(diag("UNKNOWN_REF", f"extraction zone {zone} is not in the layout", [str(zone)]))
    audit = m.get("audit")
    if not (isinstance(audit, dict) and isinstance(audit.get("backdrop"), list)
            and all(isinstance(p, str) and p for p in audit["backdrop"])):
        errs.append(diag("BAD_VALUE", "audit.backdrop must list node paths", []))
    contracts = m.get("contracts")
    if not (isinstance(contracts, list) and all(isinstance(c, str) and res_path(c).is_dir() for c in contracts)):
        errs.append(diag("MISSING_FILE", "contracts must list existing contract folders", []))
    return errs


# --- cross-checks: what is played on a location must fit it ----------------------------------------------------------

def _grid_fits(bundle: dict, grid: dict, code: str, errs: list[dict]) -> None:
    loc = bundle["manifest"]["grid"]
    kinds = {n["id"]: n["kind"] for n in loc["nodes"]}
    ends = {e["id"]: (e["from"], e["to"]) for e in loc["edges"]}
    for n in grid.get("nodes", []):
        if kinds.get(n["id"]) != n["kind"]:
            errs.append(diag(code, f"node {n['id']} ({n['kind']}) has no matching socket on this location", [n["id"]]))
    for e in grid.get("edges", []):
        if ends.get(e["id"]) != (e["from"], e["to"]):
            errs.append(diag(code, f"edge {e['id']} {e['from']}->{e['to']} is not a route on this location", [e["id"]]))


def _marker_is(idx: dict, mid: str, kind: str) -> bool:
    return idx["markers"].get(mid, {}).get("kind") == kind


def check_contract(bundle: dict, contract_dir: Path) -> list[dict]:
    """A story contract pinned to the location: its grid uses the location's sockets and routes, its repair panels,
    switches and generator anchors are layout markers of the right kind (anchors at the same position), and it
    extracts from the location's extraction zone."""
    code = "CONTRACT_MISMATCH"
    errs: list[dict] = []
    idx = _index(bundle["layout"])
    _grid_fits(bundle, _json(contract_dir / "grid.json"), code, errs)
    for r in _json(contract_dir / "repairs.json")["repairs"]:
        if not _marker_is(idx, r["panel"], "panel"):
            errs.append(diag(code, f"repair panel {r['panel']} is not a panel marker", [r["panel"]]))
    for s in _json(contract_dir / "switches.json")["switches"]:
        if not _marker_is(idx, s["id"], "switch"):
            errs.append(diag(code, f"switch {s['id']} is not a switch marker", [s["id"]]))
    eq = _json(contract_dir / "equipment.json")
    for a in eq.get("anchors", []):
        if not _marker_is(idx, a["id"], "anchor") or idx["markers"][a["id"]]["pos_cm"] != a.get("position_cm"):
            errs.append(diag(code, f"anchor {a['id']} is not an anchor marker at the same position", [a["id"]]))
    if eq.get("recovery_anchor") and not _marker_is(idx, eq["recovery_anchor"], "anchor"):
        errs.append(diag(code, "recovery_anchor is not an anchor marker", [eq["recovery_anchor"]]))
    zone = _json(contract_dir / "mission.json").get("extraction", {}).get("zone")
    if zone != bundle["manifest"]["extraction"]["zone"]:
        errs.append(diag(code, f"the contract extracts from {zone}, not the location's extraction zone", [str(zone)]))
    return errs


def check_challenge(bundle: dict, challenge: dict) -> list[dict]:
    """An RB03 challenge authored on the location (challenge.location_id): same location, grid inside the location's
    sockets and routes, fault panels, switches and temporary-supply anchors are layout markers of the right kind."""
    code = "CHALLENGE_MISMATCH"
    errs: list[dict] = []
    if challenge.get("location_id") != bundle["manifest"].get("location_id"):
        return [diag("WRONG_LOCATION", f"challenge is authored on {challenge.get('location_id')}", [str(challenge.get("id"))])]
    idx = _index(bundle["layout"])
    _grid_fits(bundle, challenge.get("grid", {}), code, errs)
    for f in challenge.get("faults", []):
        if not _marker_is(idx, f["panel"], "panel"):
            errs.append(diag(code, f"fault panel {f['panel']} is not a panel marker", [f["panel"]]))
    for s in challenge.get("switches", []):
        if not _marker_is(idx, s["id"], "switch"):
            errs.append(diag(code, f"switch {s['id']} is not a switch marker", [s["id"]]))
    for t in challenge.get("temporary_supply", []):
        for a in t.get("anchors", []):
            if not _marker_is(idx, a["id"], "anchor"):
                errs.append(diag(code, f"anchor {a['id']} is not an anchor marker", [a["id"]]))
    return errs


def check_all() -> list[str]:
    """Every location validates, and every contract it pins fits it. Returns failure lines."""
    out: list[str] = []
    kit, dims = kit_ids(), dimensions()
    found = all_locations()
    if not found:
        return ["no locations under content/locations"]
    for lid, bundle in found.items():
        for e in validate(bundle, kit, dims):
            out.append(f"{lid}: {e['code']} {e['message']}")
        if any(line.startswith(f"{lid}:") for line in out):
            continue
        for c in bundle["manifest"]["contracts"]:
            for e in check_contract(bundle, res_path(c)):
                out.append(f"{lid} {c}: {e['code']} {e['message']}")
    return out


# --- shared parity cases (tests/data/locations/cases.json) ----------------------------------------------------------

def apply_patch(bundle: dict, ops: list[dict]) -> dict:
    """Applies {"path": [...], "set": v} / {"path": [...], "delete": true} / {"path": [...], "append": v} to a copy."""
    out = copy.deepcopy(bundle)
    for op in ops:
        *head, last = op["path"]
        node: Any = out
        for k in head:
            node = node[k]
        if op.get("delete"):
            del node[last]
        elif "append" in op:
            node[last].append(copy.deepcopy(op["append"]))
        else:
            node[last] = copy.deepcopy(op["set"])
    return out


def main() -> int:
    failures = check_all()
    for line in failures:
        print("FAIL", line)
    n = len(all_locations())
    print(f"RB02 locations: {n} checked, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
