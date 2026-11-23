"""Lights Back On - challenge format, runner, solver, difficulty score and pillar checks (RB03, ADR-019).

A challenge is a data record on an authored location: a grid (the exact power rules of CLAUDE.md section 3, through
lbo_grid.Grid), faults to repair, switches, temporary supply, access latches and routes, flood areas, timed storm events,
a verification window, crew scaling and par times. Its solution trace is a list of abstract player actions
("steps") that both this runner and scripts/simulation/challenge_runner.gd replay; after every step each side emits the
SHA-256 of one canonical string (grid canonical state + run state, ADR-003 serialization) and the two must agree byte
for byte (tools/rb03_challenge_check.py).

The runner is the challenge-level twin of the host stack: repairs walk isolate -> work -> install -> restore (a
refused restore re-isolates, interaction_service.gd), latches count continuous valid supply after the grid step
(mission_director.gd), verification needs every required consumer on grid supply for verification_ticks. It does not
model positions, locks, tools, players or presentation: those belong to the host and to a location's scene.

Everything here is integer and deterministic: steps sort by stable ID, ticks are 10 Hz integers.
"""
from __future__ import annotations

import hashlib
import heapq
import json
import re
from pathlib import Path
from typing import Any

from lbo_grid import Grid, GridError, diag, serialize

ROOT = Path(__file__).resolve().parent.parent
RULES_PATH = ROOT / "content" / "challenges" / "rules.json"
SCHEMA = 1
ID_RE = re.compile(r"^[A-Z0-9_]+$")
CREWS = ("1", "2", "3", "4")
FAULT_FIX_FIELDS = {"source": ("online",), "junction": ("failed", "tripped"), "edge": ("healthy", "enabled")}
SWITCH_FIELDS = {"source": (), "junction": ("isolated", "tripped"), "consumer": ("enabled",), "edge": ("enabled",)}
# Storm grid events only ever remove supply (break, fail, cut), so the grid can never refuse them.
STORM_FIELDS = {"edge": ("healthy", False), "junction": ("failed", True), "source": ("online", False)}
STEP_KINDS = ("repair", "switch", "place", "route", "power", "access", "wait")
UNSOLVED = -1


def load_rules(path: Path = RULES_PATH) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha(s: str) -> str:
    return hashlib.sha256(s.encode("ascii")).hexdigest()


def ceil_pct(ticks: int, pct: int) -> int:
    return (ticks * pct + 99) // 100


# ---------------------------------------------------------------- schema validation

def _ids(recs: Any, where: str, errs: list[dict]) -> list[dict]:
    if not isinstance(recs, list):
        errs.append(diag("BAD_CHALLENGE", f"{where} must be a list", []))
        return []
    out = []
    for r in recs:
        if not isinstance(r, dict) or not isinstance(r.get("id"), str) or not ID_RE.match(r["id"]):
            errs.append(diag("INVALID_ID", f"{where}: every record needs an id matching ^[A-Z0-9_]+$", []))
            continue
        out.append(r)
    return out


def _int(v: Any, lo: int = 0) -> bool:
    return type(v) is int and v >= lo


def validate(doc: Any) -> list[dict]:
    """Structural and referential checks; [] means the challenge can be loaded by both runners."""
    errs: list[dict] = []
    if not isinstance(doc, dict):
        return [diag("BAD_CHALLENGE", "challenge must be an object", [])]
    if doc.get("schema") != SCHEMA:
        errs.append(diag("BAD_SCHEMA", f"schema must be {SCHEMA}", []))
    for key in ("id", "location_id"):
        if not (isinstance(doc.get(key), str) and ID_RE.match(doc[key])):
            errs.append(diag("INVALID_ID", f"{key} must match ^[A-Z0-9_]+$", []))
    try:
        g = Grid.load(doc.get("grid", {}))
    except GridError as e:
        return errs + e.diagnostics
    kind_of = {nid: n["kind"] for nid, n in g.nodes.items()} | {eid: "edge" for eid in g.edges}

    def consumers(key: str) -> list[str]:
        v = doc.get(key)
        if not isinstance(v, list) or not all(isinstance(x, str) and kind_of.get(x) == "consumer" for x in v) \
                or len(set(v)) != len(v):
            errs.append(diag("BAD_CHALLENGE", f"{key} must list distinct consumers", []))
            return []
        return v

    grid_sources = doc.get("grid_sources")
    if not (isinstance(grid_sources, list) and grid_sources and len(set(grid_sources)) == len(grid_sources)
            and all(kind_of.get(s) == "source" for s in grid_sources)):
        errs.append(diag("BAD_CHALLENGE", "grid_sources must list distinct grid sources", []))
        grid_sources = []
    required = consumers("required_consumers")
    if not required:
        errs.append(diag("BAD_CHALLENGE", "required_consumers must not be empty", []))
    excluded = consumers("excluded_loads")
    if set(required) & set(excluded):
        errs.append(diag("BAD_CHALLENGE", "a consumer cannot be both required and excluded", sorted(set(required) & set(excluded))))
    if not _int(doc.get("verification_ticks"), 1):
        errs.append(diag("BAD_VALUE", "verification_ticks must be an int >= 1", []))

    names: set[str] = set(kind_of)

    def claim(rid: str) -> None:
        if rid in names:
            errs.append(diag("DUPLICATE_ID", f"duplicate id {rid}", [rid]))
        names.add(rid)

    latches = _ids(doc.get("latches", []), "latches", errs)
    grants: set[str] = set()
    for la in latches:
        claim(la["id"])
        if kind_of.get(la.get("consumer")) != "consumer" or not _int(la.get("supplied_ticks"), 1) \
                or not (isinstance(la.get("grants"), str) and ID_RE.match(la["grants"])) \
                or not (la.get("source", "") == "" or kind_of.get(la.get("source")) == "source"):
            errs.append(diag("BAD_LATCH", f"{la['id']}: needs consumer, supplied_ticks >= 1, grants and an optional source", [la["id"]]))
            continue
        grants.add(la["grants"])
    latch_ids = {la["id"] for la in latches}
    routes = _ids(doc.get("access_routes", []), "access_routes", errs)
    for r in routes:
        claim(r["id"])
        if not (isinstance(r.get("grants"), str) and ID_RE.match(r["grants"])) \
                or r.get("requires_latch", "") not in latch_ids | {""}:
            errs.append(diag("BAD_ROUTE", f"{r['id']}: needs grants and an optional requires_latch", [r["id"]]))
            continue
        grants.add(r["grants"])
    route_ids = {r["id"] for r in routes}
    floods = _ids(doc.get("flood_areas", []), "flood_areas", errs)
    for f in floods:
        claim(f["id"])
        if not (_int(f.get("water_cm")) and _int(f.get("wade_cm")) and f.get("drained_by", "") in latch_ids | {""}):
            errs.append(diag("BAD_FLOOD", f"{f['id']}: needs water_cm, wade_cm and an optional drained_by latch", [f["id"]]))
    flood_ids = {f["id"] for f in floods}
    if grants & names:
        errs.append(diag("DUPLICATE_ID", "an access grant reuses another id", sorted(grants & names)))

    faults = _ids(doc.get("faults", []), "faults", errs)
    for f in faults:
        claim(f["id"])
        fix = f.get("fix")
        ok = isinstance(fix, dict) and kind_of.get(f.get("junction")) == "junction" and isinstance(f.get("panel"), str) \
            and ID_RE.match(f["panel"]) and _int(f.get("work_ticks")) and f.get("access", "") in grants | flood_ids | {""}
        if ok and fix.get("op") == "set":
            ok = fix.get("field") in FAULT_FIX_FIELDS.get(kind_of.get(fix.get("id"), ""), ()) and type(fix.get("value")) is bool
        elif ok and fix.get("op") == "replace_module":
            m = g.module_upgrades.get(fix.get("id"), {})
            ok = m.get("breaker") == f["junction"] and fix.get("capacity") == m.get("to_capacity")
        else:
            ok = False
        if not ok:
            errs.append(diag("BAD_FAULT", f"{f['id']}: needs panel, junction, work_ticks, a set/replace_module fix and a known access",
                             [f["id"]]))
    switches = _ids(doc.get("switches", []), "switches", errs)
    for s in switches:
        claim(s["id"])
        if s.get("field") not in SWITCH_FIELDS.get(kind_of.get(s.get("target"), ""), ()):
            errs.append(diag("BAD_SWITCH", f"{s['id']}: target field cannot be a player switch", [s["id"]]))

    temps = _ids(doc.get("temporary_supply", []), "temporary_supply", errs)
    temp_sources: set[str] = set()
    for t in temps:
        claim(t["id"])
        src = t.get("source")
        anchors = _ids(t.get("anchors", []), f"{t['id']}.anchors", errs)
        aids = [a["id"] for a in anchors]
        good = kind_of.get(src) == "source" and src not in grid_sources and src not in temp_sources \
            and not g.nodes[src]["online"] and len(set(aids)) == len(aids) and t.get("start_anchor") in aids
        for a in anchors:
            r = a.get("routes")
            if type(a.get("storage")) is not bool or not isinstance(r, list) or (a["storage"] and r) \
                    or not all(kind_of.get(e) == "edge" and not g.edges[e]["enabled"] for e in r):
                good = False
        if good and not any(a["storage"] for a in anchors if a["id"] == t["start_anchor"]):
            good = False
        if not good:
            errs.append(diag("BAD_TEMPORARY_SUPPLY", f"{t['id']}: needs an offline non-grid source, storage start anchor and "
                             "disabled route edges", [t["id"]]))
        if kind_of.get(src) == "source":
            temp_sources.add(src)
    for sid, kind in sorted(kind_of.items()):
        if kind == "source" and sid not in grid_sources and sid not in temp_sources and g.nodes[sid]["online"]:
            errs.append(diag("BAD_CHALLENGE", f"{sid}: an online source must be a grid source or temporary supply", [sid]))

    events = _ids(doc.get("storm_events", []), "storm_events", errs)
    for ev in events:
        claim(ev["id"])
        k, good = ev.get("kind"), _int(ev.get("tick"), 1)
        if k == "grid":
            cmd = ev.get("cmd") if isinstance(ev.get("cmd"), dict) else {}
            want = STORM_FIELDS.get(kind_of.get(cmd.get("id"), ""))
            good = good and cmd.get("op") == "set" and want is not None and (cmd.get("field"), cmd.get("value")) == want
        elif k == "close_route":
            good = good and ev.get("route") in route_ids and _int(ev.get("until_tick")) and ev["until_tick"] >= ev["tick"]
        elif k == "flood":
            good = good and ev.get("area") in flood_ids and _int(ev.get("water_cm"))
        else:
            good = False
        if not good:
            errs.append(diag("BAD_STORM_EVENT", f"{ev['id']}: grid (break only), close_route or flood event with a tick >= 1",
                             [ev["id"]]))
    crew = doc.get("crew_scaling")
    if not (isinstance(crew, dict) and sorted(crew) == list(CREWS) and all(_int(crew[c], 1) and crew[c] <= 100 for c in CREWS)
            and crew["1"] == 100 and all(crew[CREWS[i]] >= crew[CREWS[i + 1]] for i in range(3))):
        errs.append(diag("BAD_CREW", "crew_scaling needs work percentages for 1-4 players: 1 = 100, never rising", []))
    par = doc.get("par_ticks")
    if par is not None and not (isinstance(par, dict) and sorted(par) == list(CREWS) and all(_int(par[c], 1) for c in CREWS)):
        errs.append(diag("BAD_PAR", "par_ticks needs a tick count for 1-4 players", []))
    return errs


# ---------------------------------------------------------------- runner

class Run:
    """One playthrough of a challenge at one crew size. Mirrors scripts/simulation/challenge_runner.gd exactly."""

    def __init__(self, doc: dict, rules: dict, crew: str = "1", with_temp: bool = True) -> None:
        errs = validate(doc)
        if errs:
            raise GridError(errs)
        self.doc, self.rules, self.crew = doc, rules, crew
        self.grid = Grid.load(doc["grid"])
        self.pct = doc["crew_scaling"][crew]
        self.action_ticks = rules["action_ticks"]
        self.grid_sources = list(doc["grid_sources"])
        self.required = sorted(doc["required_consumers"])
        self.need_verify = doc["verification_ticks"]
        self.faults = {f["id"]: f for f in doc.get("faults", [])}
        self.switches = {s["id"]: s for s in doc.get("switches", [])}
        self.temps = {t["id"]: t for t in doc.get("temporary_supply", [])} if with_temp else {}
        self.anchors = {tid: {a["id"]: a for a in t["anchors"]} for tid, t in self.temps.items()}
        self.latches = {la["id"]: la for la in doc.get("latches", [])}
        self.routes = {r["id"]: r for r in doc.get("access_routes", [])}
        self.floods = {f["id"]: f for f in doc.get("flood_areas", [])}
        self.events = sorted(doc.get("storm_events", []), key=lambda e: (e["tick"], e["id"]))
        # run state (everything below is in the canonical run state)
        self.fault_state = {fid: 0 for fid in self.faults}  # 0 untouched, 1 installed (still isolated), 2 restored
        self.grants: set[str] = set()
        self.latched: dict[str, int] = {}
        self.latch_ticks = {lid: 0 for lid in self.latches}
        self.verify_ticks = 0
        self.solved_tick = UNSOLVED
        self.at = {tid: t["start_anchor"] for tid, t in self.temps.items()}
        self.used_routes: set[str] = set()
        self.water = {fid: f["water_cm"] for fid, f in self.floods.items()}
        self._roots_for: Any = None
        self._roots: dict[str, str] = {}
        self._flags_for: Any = None
        self._all_on = False
        self._latch_ok: dict[str, bool] = {}

    # ----- state
    def clone(self) -> "Run":
        r = object.__new__(Run)
        r.__dict__.update(self.__dict__)
        r.grid = self.grid.clone()
        r.fault_state, r.grants, r.latched = dict(self.fault_state), set(self.grants), dict(self.latched)
        r.latch_ticks, r.at, r.used_routes, r.water = dict(self.latch_ticks), dict(self.at), set(self.used_routes), dict(self.water)
        return r

    @property
    def now(self) -> int:
        return self.grid.tick

    def run_state(self) -> dict:
        return {"faults": dict(self.fault_state), "grants": sorted(self.grants), "latched": dict(self.latched),
                "latch_ticks": dict(self.latch_ticks), "verify_ticks": self.verify_ticks, "solved_tick": self.solved_tick,
                "temporary": dict(self.at), "used_routes": sorted(self.used_routes), "water": dict(self.water)}

    def canonical_string(self) -> str:
        return serialize({"grid": self.grid.canonical_state(), "run": self.run_state()})

    def canonical_hash(self) -> str:
        return sha(self.canonical_string())

    # ----- supply predicates (mission_director.gd _root_of/_on_grid/_latch_supplied)
    def _root(self, nid: str) -> str:
        res = self.grid.result
        if self._roots_for is not res:
            parent = {self.grid.edges[e]["to"]: self.grid.edges[e]["from"] for e in res["live"]}
            self._roots, self._roots_for = {}, res
            for n in self.grid.nodes:
                cur, guard = n, 0
                while self.grid.nodes[cur]["kind"] != "source" and cur in parent and guard <= len(self.grid.nodes):
                    cur, guard = parent[cur], guard + 1
                self._roots[n] = cur if self.grid.nodes[cur]["kind"] == "source" else ""
        return self._roots[nid]

    def _overloaded(self, sid: str) -> bool:
        return self.grid.result["load"][sid] > self.grid.nodes[sid]["capacity"]

    def on_grid(self, consumer: str) -> bool:
        if consumer not in self.grid.result["supplied"]:
            return False
        root = self._root(consumer)
        return root in self.grid_sources and (len(self.grid_sources) == 1 or not self._overloaded(root))

    def _latch_supplied(self, la: dict) -> bool:
        c = la["consumer"]
        if c not in self.grid.result["supplied"]:
            return False
        if la.get("source", ""):
            return self._root(c) == la["source"] and not self._overloaded(la["source"])
        return self.on_grid(c) if len(self.grid_sources) > 1 else True

    def all_on_grid(self) -> bool:
        res = self.grid.result
        if self._flags_for is not res:  # the evaluation only changes on apply() or a trip; cache per evaluation
            self._flags_for = res
            self._all_on = all(self.on_grid(c) for c in self.required)
            self._latch_ok = {lid: self._latch_supplied(la) for lid, la in self.latches.items()}
        return self._all_on

    def latch_ok(self, lid: str) -> bool:
        self.all_on_grid()
        return self._latch_ok[lid]

    def verified(self) -> bool:
        return self.verify_ticks >= self.need_verify

    def stowed(self) -> bool:
        return all(self.anchors[t][self.at[t]]["storage"] for t in self.temps)

    def held(self, name: str) -> bool:
        if name in self.floods:
            return self.water[name] <= self.floods[name]["wade_cm"]
        return name in self.grants

    def route_closed(self, rid: str) -> bool:
        t = self.now
        return any(e["kind"] == "close_route" and e["route"] == rid and e["tick"] <= t <= e["until_tick"] for e in self.events)

    def overloaded_any(self) -> bool:
        res, g = self.grid.result, self.grid
        return any(res["load"][s] > g.nodes[s]["capacity"] for s in res["load"])             or any(f > g.edges[e]["capacity"] for e, f in res["flow"].items())

    # ----- time
    def advance(self, n: int) -> None:
        for _ in range(n):
            self._tick()

    def _tick(self) -> None:
        now = self.grid.tick + 1
        for ev in self.events:
            if ev["tick"] != now:
                continue
            if ev["kind"] == "grid":
                self.grid.apply(ev["cmd"])  # break-only commands; the grid never refuses them
            elif ev["kind"] == "flood":
                drain = self.floods[ev["area"]].get("drained_by", "")
                if not (drain and drain in self.latched):
                    self.water[ev["area"]] = ev["water_cm"]
        self.grid.step()
        for lid in sorted(self.latches):
            if lid in self.latched:
                continue
            la = self.latches[lid]
            self.latch_ticks[lid] = self.latch_ticks[lid] + 1 if self.latch_ok(lid) else 0
            if self.latch_ticks[lid] >= la["supplied_ticks"]:
                self.latched[lid] = now
                self.grants.add(la["grants"])
                for fid in sorted(self.floods):
                    if self.floods[fid].get("drained_by", "") == lid:
                        self.water[fid] = 0
        self.verify_ticks = min(self.verify_ticks + 1, self.need_verify) if self.all_on_grid() else 0
        if self.solved_tick == UNSOLVED and self.verified() and self.stowed():
            self.solved_tick = now

    # ----- steps
    def do(self, step: dict) -> str:
        """Applies one trace step; returns "ok" or a refusal code. Every non-wait step then costs action_ticks."""
        kind = step.get("do")
        if kind == "wait":
            return self._do_wait(step)
        if kind not in STEP_KINDS:
            return "BAD_STEP"
        code = getattr(self, "_do_" + kind)(step)
        self.advance(self.action_ticks)
        return code

    def _do_wait(self, step: dict) -> str:
        """{"ticks": n} waits n ticks. {"until": "latch", "id"}, {"until": "verified"}, {"until": "solved"} and
        {"until": "tick", "tick"} wait for a condition, so one trace replays at every crew size; a condition that does
        not come within rules.wait_limit_ticks is refused with WAIT_TIMEOUT (the time is spent)."""
        until = step.get("until")
        if until is None:
            if not _int(step.get("ticks"), 1):
                return "BAD_STEP"
            self.advance(step["ticks"])
            return "ok"
        if until == "latch" and step.get("id") in self.latches:
            def done() -> bool:
                return step["id"] in self.latched
        elif until == "verified":
            def done() -> bool:
                return self.verified()
        elif until == "solved":
            def done() -> bool:
                return self.solved_tick != UNSOLVED
        elif until == "tick" and _int(step.get("tick"), 1):
            def done() -> bool:
                return self.now >= step["tick"]
        else:
            return "BAD_STEP"
        for _ in range(self.rules["wait_limit_ticks"]):
            if done():
                return "ok"
            self._tick()
        return "ok" if done() else "WAIT_TIMEOUT"

    def _set(self, rid: str, field: str, value: bool) -> str:
        r = self.grid.apply({"op": "set", "id": rid, "field": field, "value": value})
        return "ok" if r["ok"] else r["code"]

    def _field(self, rid: str, field: str) -> bool:
        rec = self.grid.nodes.get(rid) or self.grid.edges[rid]
        return rec[field]

    def _do_repair(self, step: dict) -> str:
        f = self.faults.get(step.get("id"))
        if f is None:
            return "UNKNOWN_ID"
        fid, j = f["id"], f["junction"]
        if self.fault_state[fid] == 2:
            return "ALREADY_RESTORED"
        if f.get("access", "") and not self.held(f["access"]):
            return "ACCESS_BLOCKED"
        if self.fault_state[fid] == 0:
            code = self._set(j, "isolated", True)
            if code != "ok":
                return code
            self.advance(ceil_pct(f["work_ticks"], self.pct))
            r = self.grid.apply(f["fix"])
            if not r["ok"]:
                return r["code"]
            self.fault_state[fid] = 1
        was_isolated = self._field(j, "isolated")
        code = self._set(j, "isolated", False)
        if code != "ok":
            return code
        if self._field(j, "tripped"):
            code = self._set(j, "tripped", False)
            if code != "ok":
                if was_isolated:
                    self._set(j, "isolated", True)  # re-isolating only removes supply; keeps restore atomic
                return code
        self.fault_state[fid] = 2
        return "ok"

    def _do_switch(self, step: dict) -> str:
        s = self.switches.get(step.get("id"))
        if s is None:
            return "UNKNOWN_ID"
        if type(step.get("value")) is not bool:
            return "BAD_STEP"
        if self._field(s["target"], s["field"]) == step["value"]:
            return "NO_CHANGE"
        return self._set(s["target"], s["field"], step["value"])

    def _temp(self, step: dict) -> dict | None:
        return self.temps.get(step.get("id"))

    def _do_place(self, step: dict) -> str:
        t = self._temp(step)
        if t is None:
            return "UNKNOWN_ID"
        a = step.get("anchor")
        if a not in self.anchors[t["id"]]:
            return "UNKNOWN_ANCHOR"
        if a == self.at[t["id"]]:
            return "NO_CHANGE"
        if self.grid.nodes[t["source"]]["online"]:
            return "SUPPLY_RUNNING"
        if any(self.grid.edges[e]["enabled"] for e in self.anchors[t["id"]][self.at[t["id"]]]["routes"]):
            return "ROUTES_CONNECTED"
        self.advance(ceil_pct(self.rules["carry_ticks"], self.pct))
        self.at[t["id"]] = a
        return "ok"

    def _do_route(self, step: dict) -> str:
        t = self._temp(step)
        if t is None:
            return "UNKNOWN_ID"
        e, on = step.get("edge"), step.get("on")
        if type(on) is not bool:
            return "BAD_STEP"
        if e not in self.anchors[t["id"]][self.at[t["id"]]]["routes"]:
            return "ROUTE_NOT_AT_ANCHOR"
        if self.grid.edges[e]["enabled"] == on:
            return "NO_CHANGE"
        return self._set(e, "enabled", on)

    def _do_power(self, step: dict) -> str:
        t = self._temp(step)
        if t is None:
            return "UNKNOWN_ID"
        on = step.get("on")
        if type(on) is not bool:
            return "BAD_STEP"
        if self.grid.nodes[t["source"]]["online"] == on:
            return "NO_CHANGE"
        if on and self.anchors[t["id"]][self.at[t["id"]]]["storage"]:
            return "NOT_PLACED"
        return self._set(t["source"], "online", on)

    def _do_access(self, step: dict) -> str:
        r = self.routes.get(step.get("id"))
        if r is None:
            return "UNKNOWN_ID"
        if r["id"] in self.used_routes:
            return "NO_CHANGE"
        if r.get("requires_latch", "") and r["requires_latch"] not in self.latched:
            return "ACCESS_NOT_READY"
        if self.route_closed(r["id"]):
            return "ROUTE_CLOSED"
        self.used_routes.add(r["id"])
        self.grants.add(r["grants"])
        return "ok"

    # ----- candidate steps (solver, failing-route census, marker policy)
    def candidate_steps(self) -> list[dict]:
        out: list[dict] = []
        for fid in sorted(self.faults):
            f = self.faults[fid]
            if self.fault_state[fid] < 2 and (not f.get("access", "") or self.held(f["access"])):
                out.append({"do": "repair", "id": fid})
        for rid in sorted(self.routes):
            r = self.routes[rid]
            if rid not in self.used_routes and (not r.get("requires_latch", "") or r["requires_latch"] in self.latched) \
                    and not self.route_closed(rid):
                out.append({"do": "access", "id": rid})
        for sid in sorted(self.switches):
            s = self.switches[sid]
            out.append({"do": "switch", "id": sid, "value": not self._field(s["target"], s["field"])})
        for tid in sorted(self.temps):
            t, here = self.temps[tid], self.anchors[tid][self.at[tid]]
            online = self.grid.nodes[t["source"]]["online"]
            connected = [e for e in here["routes"] if self.grid.edges[e]["enabled"]]
            if not online and not connected:
                out += [{"do": "place", "id": tid, "anchor": a} for a in sorted(self.anchors[tid]) if a != self.at[tid]]
            out += [{"do": "route", "id": tid, "edge": e, "on": not self.grid.edges[e]["enabled"]} for e in sorted(here["routes"])]
            if online or not here["storage"]:
                out.append({"do": "power", "id": tid, "on": not online})
        return out

    def next_wait(self) -> dict | None:
        """The semantic wait for the next thing that waiting can change (earliest first): a storm event or route
        reopening, a latch completing, verification (or the finish once everything is stowed). None if nothing will."""
        best: tuple[int, int, dict] | None = None

        def offer(ticks: int, rank: int, step: dict) -> None:
            nonlocal best
            if ticks >= 1 and (best is None or (ticks, rank) < best[:2]):
                best = (ticks, rank, step)

        for ev in self.events:
            for t in (ev["tick"], ev.get("until_tick", ev["tick"]) + 1):
                offer(t - self.now, 0, {"do": "wait", "until": "tick", "tick": t})
        for lid in sorted(self.latches):
            if lid not in self.latched and self.latch_ok(lid):
                offer(self.latches[lid]["supplied_ticks"] - self.latch_ticks[lid], 1, {"do": "wait", "until": "latch", "id": lid})
        if self.all_on_grid() and not self.verified():
            step = {"do": "wait", "until": "solved"} if self.stowed() else {"do": "wait", "until": "verified"}
            offer(self.need_verify - self.verify_ticks, 2, step)
        return best[2] if best else None


def replay(doc: dict, trace: dict, rules: dict, crew: str = "1") -> tuple[Run, list[list[str]]]:
    """Replays trace["steps"]; returns the run and one record per step [index, do, outcome, tick, hash]."""
    run = Run(doc, rules, crew)
    recs: list[list[str]] = []
    for i, step in enumerate(trace["steps"]):
        out = run.do(step)
        recs.append([str(i), str(step.get("do")), out, str(run.now), run.canonical_hash()])
    return run, recs


def check_trace(doc: dict, trace: dict, rules: dict) -> list[str]:
    """Replays at every crew size; returns mismatches (empty = the trace solves the challenge exactly as recorded)."""
    out: list[str] = []
    for crew in CREWS:
        run, recs = replay(doc, trace, rules, crew)
        for (i, kind, got, _t, _h), step in zip(recs, trace["steps"]):
            if got != step.get("expect", "ok"):
                out.append(f"crew {crew} step {i} ({kind}): expected {step.get('expect', 'ok')}, got {got}")
        if run.solved_tick == UNSOLVED and trace.get("must_solve", True):
            out.append(f"crew {crew}: not solved after {run.now} ticks")
        want = trace.get("solved_ticks", {}).get(crew)
        if want is not None and want != run.solved_tick:
            out.append(f"crew {crew}: solved at tick {run.solved_tick}, trace says {want}")
    return out


# ---------------------------------------------------------------- solver

def _discrete_key(run: Run) -> str:
    """Everything that defines what a state can still do, except the time-like counters (latch and verification ticks),
    which the solver compares by dominance instead. Mutable grid fields only: the evaluation is derived from them."""
    g = run.grid
    nodes = {nid: [n[f] for f in ("online", "isolated", "failed", "tripped", "enabled", "healthy") if f in n]
             for nid, n in g.nodes.items()}
    edges = {eid: [e["enabled"], e["healthy"], e["capacity"]] for eid, e in g.edges.items()}
    phase = sum(1 for e in run.events for t in (e["tick"], e.get("until_tick", e["tick"]) + 1) if t <= run.now)
    return repr((sorted(nodes.items()), sorted(edges.items()), sorted(g.overload_ticks.items()),
                 sorted(run.fault_state.items()), sorted(run.grants), sorted(run.latched), sorted(run.at.items()),
                 sorted(run.used_routes), sorted(run.water.items()), phase, run.solved_tick != UNSOLVED))


def _counters(run: Run) -> tuple[int, ...]:
    return tuple(run.latch_ticks[lid] for lid in sorted(run.latch_ticks)) + (run.verify_ticks,)


def _dominated(entries: list[tuple[int, tuple[int, ...]]], now: int, c: tuple[int, ...]) -> bool:
    """A state is dominated by an earlier one with the same discrete key and counters at least as high: from the earlier
    state a crew could simply wait, and more continuous supply never closes an option (latches only grant access)."""
    return any(t <= now and all(a >= b for a, b in zip(ec, c)) for t, ec in entries)


def _useless(run: Run, step: dict) -> bool:
    """Switching on a load that is neither required nor a latch target only adds demand; it can never help a solution."""
    if step["do"] != "switch" or not step["value"]:
        return False
    s = run.switches[step["id"]]
    return s["field"] == "enabled" and s["target"] in run.grid.nodes and s["target"] not in run.required         and all(la["consumer"] != s["target"] for la in run.latches.values())


def _lower_bound(run: Run) -> int:
    """Admissible A* bound on the ticks still needed: the rest of the verification window (it restarts from zero while
    any required consumer is off grid supply) and, overlapping it, stowing every temporary supply."""
    verify = run.need_verify - run.verify_ticks if run.all_on_grid() else run.need_verify
    stow = 0
    for tid in sorted(run.temps):
        here = run.anchors[tid][run.at[tid]]
        if here["storage"]:
            continue
        stow += run.action_ticks * (int(run.grid.nodes[run.temps[tid]["source"]]["online"])
                                    + sum(1 for e in here["routes"] if run.grid.edges[e]["enabled"]) + 1)
        stow += ceil_pct(run.rules["carry_ticks"], run.pct)
    return max(verify, stow) if run.solved_tick == UNSOLVED else 0


def solve(doc: dict, rules: dict, with_temp: bool = True) -> dict:
    """Least-ticks solution (ties: fewest steps) by A* search over player steps, crew of one.
    A step that is refused or leaves any source or edge overloaded is never taken (it is a failing route).
    Returns {"status": "solved", "steps", "ticks", "states"}, {"status": "unsolvable", "states"} when the whole reachable
    space was searched, or {"status": "limit", "states"} when rules.solver limits stopped the search (never read as
    proof that no solution exists)."""
    limits = rules["solver"]
    start = Run(doc, rules, "1", with_temp)
    heap: list[tuple[int, int, int, Run, list[dict]]] = [(_lower_bound(start), 0, 0, start, [])]
    best: dict[str, list[tuple[int, tuple[int, ...]]]] = {_discrete_key(start): [(0, _counters(start))]}
    states, seq, capped = 1, 0, False
    while heap:
        _bound, nsteps, _, run, steps = heapq.heappop(heap)
        if run.solved_tick != UNSOLVED:
            return {"status": "solved", "steps": steps, "ticks": run.solved_tick, "states": states}
        options = [c for c in run.candidate_steps() if not _useless(run, c)]
        w = run.next_wait()
        if w:
            options.append(w)
        for step in options:
            nxt = run.clone()
            if nxt.do(step) != "ok" or nxt.overloaded_any():
                continue
            if nxt.now > limits["max_ticks"]:
                capped = True
                continue
            key, c = _discrete_key(nxt), _counters(nxt)
            entries = best.setdefault(key, [])
            if _dominated(entries, nxt.now, c):
                continue
            entries.append((nxt.now, c))
            states += 1
            if states > limits["max_states"]:
                return {"status": "limit", "states": states}
            seq += 1
            heapq.heappush(heap, (nxt.now + _lower_bound(nxt), nsteps + 1, seq, nxt, steps + [step]))
    return {"status": "limit" if capped else "unsolvable", "states": states}


def _first_divergence(doc: dict, rules: dict, steps: list[dict]) -> tuple[int, str, Run] | None:
    """First (step index, crew, run just before that step) where a larger crew's outcome differs from the expected one."""
    for crew in CREWS[1:]:
        run = Run(doc, rules, crew)
        for i, step in enumerate(steps):
            before = run.clone()
            if run.do(step) != step.get("expect", "ok"):
                return i, crew, before
    return None


def harden(doc: dict, rules: dict, steps: list[dict]) -> list[dict]:
    """Makes a crew-of-one solution replay at every crew size. A bigger crew works faster, so a step that relied on
    time passing (a latch completing, a storm passing) may come too early; before such a step insert the wait it
    depends on: the latch that unlocks it, else 'until the tick the solo crew reached it'. Both cost the solo crew
    nothing (the condition already holds), so the answer never changes with crew size."""
    steps = [dict(s) for s in steps]
    solo = Run(doc, rules, "1")
    start_tick: list[int] = []
    for s in steps:
        start_tick.append(solo.now)
        solo.do(s)
    for _ in range(4 * len(steps) + 4):
        hit = _first_divergence(doc, rules, steps)
        if hit is None:
            return steps
        i, _crew, before = hit
        wait: dict = {"do": "wait", "until": "tick", "tick": max(1, start_tick[i])}
        latch = _unlocking_latch(before, steps[i])
        prev = steps[i - 1] if i else {}
        if latch and not (prev.get("until") == "latch" and prev.get("id") == latch):
            wait = {"do": "wait", "until": "latch", "id": latch}
        if prev == wait or (prev.get("until") == "tick" and wait.get("until") == "tick"):
            return steps  # no further hardening possible; the validator reports the crew that fails
        steps.insert(i, wait)
        start_tick.insert(i, start_tick[i])
    return steps


def _unlocking_latch(run: Run, step: dict) -> str:
    """The latch whose completion lets this step through, if waiting for one is what it needs."""
    need = ""
    if step.get("do") == "access" and step.get("id") in run.routes:
        need = run.routes[step["id"]].get("requires_latch", "")
        return need if need and need not in run.latched else ""
    if step.get("do") == "repair" and step.get("id") in run.faults:
        access = run.faults[step["id"]].get("access", "")
        if access and not run.held(access):
            if access in run.floods:
                need = run.floods[access].get("drained_by", "")
            else:
                need = next((lid for lid in sorted(run.latches) if run.latches[lid]["grants"] == access), "")
    return need if need and need not in run.latched else ""


def make_trace(doc: dict, rules: dict, solution: dict) -> dict:
    """Solution trace document: the hardened steps plus the tick each crew size finishes at (replayed, not estimated)."""
    trace = {"challenge_id": doc["id"], "steps": harden(doc, rules, solution["steps"])}
    trace["solved_ticks"] = {c: replay(doc, trace, rules, c)[0].solved_tick for c in CREWS}
    return trace


def par_ticks(trace: dict, rules: dict) -> dict:
    return {c: ceil_pct(trace["solved_ticks"][c], rules["par_margin_pct"]) for c in CREWS}


# ---------------------------------------------------------------- difficulty

def _sig(step: dict) -> str:
    return serialize({k: v for k, v in step.items() if k not in ("expect", "ticks")})


def _downstream_demand(g: Grid, nid: str) -> int:
    n = g.nodes[nid]
    if n["kind"] == "consumer":
        return n["demand"]
    if n["kind"] == "source":
        return 0
    return sum(_downstream_demand(g, e["to"]) for _, e in sorted(g.edges.items()) if e["from"] == nid)


def _contended(doc: dict, temp: dict) -> bool:
    """True when the temporary source cannot carry every route at one anchor at once (pillar 2)."""
    g = Grid.load(doc["grid"])
    cap = g.nodes[temp["source"]]["capacity"]
    return any(sum(_downstream_demand(g, g.edges[e]["to"]) for e in a["routes"]) > cap for a in temp["anchors"])


def _marker_visible(doc: dict, fault: dict) -> bool:
    """A fault the dark-building marker points straight at: it sits on the junction or service drop that feeds a
    required consumer directly. Anything further up (a trunk, a source, a feeder module) needs the meter."""
    g = Grid.load(doc["grid"])
    fix = fault["fix"]
    req = set(doc["required_consumers"])
    if fix["op"] == "set" and fix["id"] in g.edges:
        return g.edges[fix["id"]]["to"] in req
    if fix["op"] == "set" and g.nodes[fix["id"]]["kind"] == "junction":
        return any(e["from"] == fix["id"] and e["to"] in req for e in g.edges.values())
    return False


def analyse(doc: dict, trace: dict, rules: dict) -> dict:
    """Measures the difficulty inputs from the solution (plan: steps, tradeoffs, failing routes, meter readings,
    time pressure), the score, the tier and the pillar verdicts."""
    run = Run(doc, rules, "1")
    traps: dict[str, str] = {}
    trap_elements: set[str] = set()
    used_temps: set[str] = set()
    energized_routes: dict[str, set[str]] = {}
    states: list[str] = []
    for step in trace["steps"]:
        for cand in run.candidate_steps():
            if _sig(cand) in traps:
                continue
            probe = run.clone()
            code = probe.do(cand)
            if code != "ok":
                traps[_sig(cand)] = code
            elif probe.overloaded_any():
                traps[_sig(cand)] = "OVERLOAD"
                trap_elements.update(probe.grid.overloads())
        states.append(_shape(run))
        run.do(step)
        if step["do"] == "power" and step["on"]:
            used_temps.add(step["id"])
        if step["do"] == "route" and step["on"]:
            energized_routes.setdefault(step["id"], set()).add(step["edge"])
    states.append(_shape(run))
    temps = {t["id"]: t for t in doc.get("temporary_supply", [])}
    temp_required = bool(temps) and solve(doc, rules, with_temp=False)["status"] == "unsolvable"
    contended = {tid for tid in used_temps if _contended(doc, temps[tid])}
    tradeoffs = sum(len(energized_routes.get(tid, ())) for tid in sorted(contended)) if temp_required else 0
    repaired = [s["id"] for s in trace["steps"] if s["do"] == "repair"]
    faults = {f["id"]: f for f in doc.get("faults", [])}
    hidden = sorted({faults[f]["panel"] for f in repaired if not _marker_visible(doc, faults[f])})
    solved = trace["solved_ticks"]["1"]
    timed = [e for e in doc.get("storm_events", []) if e["tick"] <= solved]
    metrics = {"steps": sum(1 for s in trace["steps"] if s["do"] != "wait"), "tradeoffs": tradeoffs,
               "failing_routes": len(traps), "meter_readings": len(hidden) + len(trap_elements),
               "time_pressure": len(timed)}
    w = rules["score_weights"]
    score = sum(w[k] * metrics[k] for k in sorted(w))
    tier = max(i + 1 for i, lo in enumerate(rules["tier_min_scores"]) if score >= lo)
    pillars = []
    if marker_policy_solves(doc, rules) or metrics["meter_readings"] == 0:
        pillars.append("MARKER_ONLY")
    if not temp_required or not contended:
        pillars.append("NO_TRADEOFF")
    start = Run(doc, rules, "1")
    if start.all_on_grid():
        pillars.append("NO_VISIBLE_RECOVERY")
    return {"metrics": metrics, "score": score, "tier": tier, "pillar_failures": pillars,
            "temp_required": temp_required, "hidden_fault_panels": hidden, "trap_elements": sorted(trap_elements),
            "failing_routes": sorted(traps.items()), "puzzle_hash": puzzle_hash(doc),
            "near_duplicate_hash": sha(serialize(states))}


# ---------------------------------------------------------------- pillar 1: the marker-following player

ON_SENSE = {"isolated": False, "tripped": False, "enabled": True}


def marker_policy_solves(doc: dict, rules: dict) -> bool:
    """A player who only follows markers and holds Interact: repair whatever is reachable, take every open route, flip
    every switch to 'on', drop the generator at the first pad and connect every cable, stow once the street is lit.
    No meter, no choice. If this finishes the challenge, pillar 1 fails (CLAUDE.md section 2)."""
    pol = rules["marker_policy"]
    run = Run(doc, rules, "1")
    tried: set[str] = set()
    while run.solved_tick == UNSOLVED and run.now < pol["max_ticks"]:
        step = _marker_step(run, tried)
        if step is None:
            run.advance(pol["idle_ticks"])
            continue
        tried.add(_sig(step) + "@" + _discrete_key(run))
        run.do(step)
    return run.solved_tick != UNSOLVED


def _marker_step(run: Run, tried: set[str]) -> dict | None:
    key = _discrete_key(run)
    lit = run.all_on_grid()
    wanted: list[dict] = []
    for c in run.candidate_steps():
        if c["do"] in ("repair", "access"):
            wanted.append(c)
        elif c["do"] == "switch":
            s = run.switches[c["id"]]
            if c["value"] == ON_SENSE[s["field"]]:
                wanted.append(c)
    for tid in sorted(run.temps):
        t, here = run.temps[tid], run.anchors[tid][run.at[tid]]
        online = run.grid.nodes[t["source"]]["online"]
        if not lit:
            pads = [a for a in sorted(run.anchors[tid]) if not run.anchors[tid][a]["storage"]]
            if here["storage"] and pads:
                wanted.append({"do": "place", "id": tid, "anchor": pads[0]})
            wanted += [{"do": "route", "id": tid, "edge": e, "on": True} for e in sorted(here["routes"])
                       if not run.grid.edges[e]["enabled"]]
            if not here["storage"] and not online:
                wanted.append({"do": "power", "id": tid, "on": True})
        else:
            if online:
                wanted.append({"do": "power", "id": tid, "on": False})
            wanted += [{"do": "route", "id": tid, "edge": e, "on": False} for e in sorted(here["routes"])
                       if run.grid.edges[e]["enabled"]]
            stores = [a for a in sorted(run.anchors[tid]) if run.anchors[tid][a]["storage"]]
            if not here["storage"]:
                wanted.append({"do": "place", "id": tid, "anchor": stores[0]})
    for step in wanted:
        if _sig(step) + "@" + key not in tried:
            return step
    return None


# ---------------------------------------------------------------- duplicates

PUZZLE_META = ("id", "location_id", "source_contract", "source_note", "par_ticks", "name_key")


def puzzle_hash(doc: dict) -> str:
    """Exact-duplicate hash: the challenge without its names, notes, par and source pin."""
    return sha(serialize({k: v for k, v in doc.items() if k not in PUZZLE_META}))


def _shape(run: Run) -> dict:
    """The boolean shape of one solution state: every supply flag and run fact, no numbers. Two challenges whose
    solutions walk through the same shapes are the same puzzle with re-tuned capacities (a near-duplicate)."""
    st = run.grid.canonical_state()
    flags = {gid: {k: v for k, v in rec.items() if type(v) is bool} for grp in ("nodes", "edges") for gid, rec in st[grp].items()}
    return {"flags": flags, "faults": dict(run.fault_state), "grants": sorted(run.grants), "latched": sorted(run.latched),
            "temporary": dict(run.at), "used_routes": sorted(run.used_routes), "verified": run.verified()}


def near_duplicates(analyses: dict[str, dict]) -> list[tuple[str, str, str]]:
    """[(kept, rejected, reason)] in ID order: a later challenge with the same puzzle or solution-shape hash is rejected."""
    out: list[tuple[str, str, str]] = []
    first: dict[str, str] = {}
    for cid in sorted(analyses):
        for kind in ("puzzle_hash", "near_duplicate_hash"):
            h = analyses[cid][kind]
            if h in first:
                out.append((first[h], cid, kind))
                break
        else:
            first[analyses[cid]["puzzle_hash"]] = cid
            first[analyses[cid]["near_duplicate_hash"]] = cid
    return out


# ---------------------------------------------------------------- story contracts -> challenge format

def _json(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8"))


def from_contract(contract_dir: Path, rules: dict) -> dict:
    """Builds the challenge-format view of a story contract (content/contracts/cNN_*). Optional objectives, stars,
    venues, finale and presentation are not part of the puzzle and are left out; see docs/evidence/RB03.md."""
    grid, mission = _json(contract_dir / "grid.json"), _json(contract_dir / "mission.json")
    repairs, switches = _json(contract_dir / "repairs.json"), _json(contract_dir / "switches.json")
    equipment = _json(contract_dir / "equipment.json")
    cid = mission["contract_id"]
    doc: dict = {"schema": SCHEMA, "id": f"STORY_{cid}", "location_id": f"CONTRACT_{cid}", "source_contract": cid,
                 "grid": {k: v for k, v in grid.items() if k not in ("contract_id", "source_note")},
                 "grid_sources": list(mission.get("grid_sources", [mission["grid_source"]])),
                 "required_consumers": sorted(mission["required_consumers"]),
                 "excluded_loads": sorted(mission.get("excluded_loads", [])),
                 "verification_ticks": mission["final_verification_ticks"]}
    doc["faults"] = [{"id": r["id"], "panel": r["panel"], "junction": r["isolate"], "fix": r["fix"],
                      "access": r.get("access", ""), "work_ticks": sum(r.get("hold_ticks", {}).values())}
                     for r in repairs["repairs"]]
    doc["switches"] = [{"id": s["id"], "target": s["target"], "field": s["field"]} for s in switches["switches"]]
    anchors = equipment.get("anchors", [])
    doc["temporary_supply"] = [{"id": e["id"], "source": e["source"], "start_anchor": e["start_anchor"],
                                "anchors": [{"id": a["id"], "storage": a["storage"], "routes": list(a["routes"])} for a in anchors]}
                               for e in equipment.get("equipment", []) if e["kind"] == "generator"]
    doc["latches"] = [{k: la[k] for k in ("id", "consumer", "source", "supplied_ticks", "grants") if k in la}
                      for la in mission.get("access_latches", [])]
    routes: list[dict] = [{"id": ld["id"], "grants": ld["grants"], "requires_latch": ld.get("requires_latch", "")}
                          for ld in mission.get("fixed_ladders", [])]
    events: list[dict] = []
    wind = mission.get("wind_routes")
    if wind:
        routes.append({"id": wind["roof_route"], "grants": wind["grants"], "requires_latch": ""})
        routes.append({"id": wind["ground_route"], "grants": wind["grants"], "requires_latch": ""})
        events.append({"id": "STORM_" + wind["roof_route"] + "_GUSTS", "kind": "close_route", "route": wind["roof_route"],
                       "tick": wind["close_start_ticks"], "until_tick": wind["close_end_ticks"]})
    doc["access_routes"] = routes
    doc["flood_areas"] = []
    doc["storm_events"] = events
    doc["crew_scaling"] = dict(rules["crew_work_pct"])
    return doc
