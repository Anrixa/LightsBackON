extends RefCounted
## Replays a challenge solution trace (RB03, ADR-019): the GDScript twin of reference/lbo_challenge.py Run.
##
## No scene tree, no autoloads: grid rules come from power_grid.gd, so the exact power rules (CLAUDE.md section 3) are
## the ones the host runs. After every step the canonical string (grid canonical state + run state, ADR-003
## serialization) must match the Python reference byte for byte (tools/rb03_challenge_check.py). Keep the two in step:
## a change here is a change there.
##
## Semantics mirror the host stack without positions, locks or tools: a repair isolates its junction, spends its work
## time, installs the fix and restores (a refused breaker reset re-isolates, interaction_service.gd); latches count
## continuous valid supply after the grid step and verification needs every required consumer on grid supply for
## verification_ticks (mission_director.gd). The full schema check lives in the Python reference (validate()); this
## loader refuses anything it cannot run.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")

const UNSOLVED: int = -1
const CREWS: Array[String] = ["1", "2", "3", "4"]

var grid: PowerGrid = PowerGrid.new()
var solved_tick: int = UNSOLVED

var _rules: Dictionary = {}
var _pct: int = 100
var _action_ticks: int = 1
var _grid_sources: Array[String] = []
var _required: Array[String] = []
var _need_verify: int = 1
var _faults: Dictionary = {}
var _switches: Dictionary = {}
var _temps: Dictionary = {}
var _anchors: Dictionary = {}  # temp id -> {anchor id -> record}
var _latches: Dictionary = {}
var _routes: Dictionary = {}
var _floods: Dictionary = {}
var _events: Array[Dictionary] = []  # sorted by (tick, id)
# run state (canonical)
var _fault_state: Dictionary = {}
var _grants: Dictionary = {}
var _latched: Dictionary = {}
var _latch_ticks: Dictionary = {}
var _verify_ticks: int = 0
var _at: Dictionary = {}
var _used_routes: Dictionary = {}
var _water: Dictionary = {}
# supply flags of the current grid evaluation; it only changes on apply() and on a trip
var _dirty: bool = true
var _st: Dictionary = {}
var _roots: Dictionary = {}
var _all_on: bool = false
var _latch_ok: Dictionary = {}


static func json(path: String) -> Dictionary:
	return PowerGrid.json_ints(JSON.parse_string(FileAccess.get_file_as_string(path)))


## Loads a challenge for one crew size ("1".."4"). Returns diagnostics; empty means ready to replay.
func load_challenge(doc: Dictionary, rules: Dictionary, crew: String) -> Array[Dictionary]:
	var errs: Array[Dictionary] = []
	doc = PowerGrid.json_ints(doc)
	_rules = PowerGrid.json_ints(rules)
	errs.append_array(grid.load_definition(doc.get("grid", {})))
	if not errs.is_empty():
		return errs
	var crew_scaling: Dictionary = doc.get("crew_scaling", {})
	if not (CREWS.has(crew) and crew_scaling.get(crew) is int):
		return [PowerGrid.diag("BAD_CREW", "crew_scaling has no work percentage for %s" % crew, [])]
	_pct = crew_scaling[crew]
	_action_ticks = int(_rules["action_ticks"])
	_grid_sources.assign(doc.get("grid_sources", []))
	_required.assign(doc.get("required_consumers", []))
	_required.sort()
	_need_verify = int(doc.get("verification_ticks", 0))
	var st: Dictionary = grid.canonical_state()
	for f: Dictionary in doc.get("faults", []):
		_faults[f["id"]] = f
		_fault_state[f["id"]] = 0
		if not st["nodes"].has(f.get("junction", "")):
			errs.append(PowerGrid.diag("BAD_FAULT", "%s: unknown junction" % f["id"], [f["id"]]))
	for s: Dictionary in doc.get("switches", []):
		_switches[s["id"]] = s
		if not (st["nodes"].has(s.get("target", "")) or st["edges"].has(s.get("target", ""))):
			errs.append(PowerGrid.diag("BAD_SWITCH", "%s: unknown target" % s["id"], [s["id"]]))
	for t: Dictionary in doc.get("temporary_supply", []):
		_temps[t["id"]] = t
		var by_id: Dictionary = {}
		for a: Dictionary in t.get("anchors", []):
			by_id[a["id"]] = a
		_anchors[t["id"]] = by_id
		_at[t["id"]] = t.get("start_anchor", "")
		if not (by_id.has(_at[t["id"]]) and st["nodes"].has(t.get("source", ""))):
			errs.append(PowerGrid.diag("BAD_TEMPORARY_SUPPLY", "%s: unknown source or start anchor" % t["id"], [t["id"]]))
	for la: Dictionary in doc.get("latches", []):
		_latches[la["id"]] = la
		_latch_ticks[la["id"]] = 0
		if not st["nodes"].has(la.get("consumer", "")):
			errs.append(PowerGrid.diag("BAD_LATCH", "%s: unknown consumer" % la["id"], [la["id"]]))
	for r: Dictionary in doc.get("access_routes", []):
		_routes[r["id"]] = r
	for f: Dictionary in doc.get("flood_areas", []):
		_floods[f["id"]] = f
		_water[f["id"]] = int(f["water_cm"])
	for ev: Dictionary in doc.get("storm_events", []):
		_events.append(ev)
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["tick"]) != int(b["tick"]):
			return int(a["tick"]) < int(b["tick"])
		return str(a["id"]) < str(b["id"]))
	for c: String in _required + _grid_sources:
		if not st["nodes"].has(c):
			errs.append(PowerGrid.diag("BAD_CHALLENGE", "unknown node %s" % c, [c]))
	return errs


# ---------- state ----------

func now() -> int:
	return grid.tick


func run_state() -> Dictionary:
	return {"faults": _fault_state.duplicate(), "grants": _sorted(_grants.keys()), "latched": _latched.duplicate(),
		"latch_ticks": _latch_ticks.duplicate(), "verify_ticks": _verify_ticks, "solved_tick": solved_tick,
		"temporary": _at.duplicate(), "used_routes": _sorted(_used_routes.keys()), "water": _water.duplicate()}


func canonical_string() -> String:
	return PowerGrid.serialize({"grid": grid.canonical_state(), "run": run_state()})


func canonical_hash() -> String:
	return canonical_string().sha256_text()


# ---------- supply predicates (mission_director.gd _root_of / _on_grid / _latch_supplied) ----------

func _refresh() -> void:
	if not _dirty:
		return
	_dirty = false
	_st = grid.canonical_state()
	var parent: Dictionary = {}
	for eid: String in _st["edges"]:
		var e: Dictionary = _st["edges"][eid]
		if e["energized"]:
			parent[e["to"]] = e["from"]
	_roots = {}
	var nodes: Dictionary = _st["nodes"]
	for nid: String in nodes:
		var cur: String = nid
		var guard: int = 0
		while nodes[cur]["kind"] != PowerGrid.KIND_SOURCE and parent.has(cur) and guard <= nodes.size():
			cur = parent[cur]
			guard += 1
		_roots[nid] = cur if nodes[cur]["kind"] == PowerGrid.KIND_SOURCE else ""
	_all_on = true
	for c: String in _required:
		if not _on_grid(c):
			_all_on = false
	_latch_ok = {}
	for lid: String in _latches:
		_latch_ok[lid] = _latch_supplied(_latches[lid])


func _overloaded(sid: String) -> bool:
	return _st["nodes"][sid]["overloaded"]


func _on_grid(consumer: String) -> bool:
	if not _st["nodes"][consumer]["supplied"]:
		return false
	var root: String = _roots[consumer]
	return _grid_sources.has(root) and (_grid_sources.size() == 1 or not _overloaded(root))


func _latch_supplied(la: Dictionary) -> bool:
	var c: String = la["consumer"]
	if not _st["nodes"][c]["supplied"]:
		return false
	var src: String = la.get("source", "")
	if src != "":
		return _roots[c] == src and not _overloaded(src)
	return _on_grid(c) if _grid_sources.size() > 1 else true


func all_on_grid() -> bool:
	_refresh()
	return _all_on


func verified() -> bool:
	return _verify_ticks >= _need_verify


func stowed() -> bool:
	for tid: String in _temps:
		if not _anchors[tid][_at[tid]]["storage"]:
			return false
	return true


func _held(name: String) -> bool:
	if _floods.has(name):
		return int(_water[name]) <= int(_floods[name]["wade_cm"])
	return _grants.has(name)


func _route_closed(rid: String) -> bool:
	var t: int = grid.tick
	for ev: Dictionary in _events:
		if ev["kind"] == "close_route" and ev["route"] == rid and int(ev["tick"]) <= t and t <= int(ev["until_tick"]):
			return true
	return false


# ---------- time ----------

func advance(n: int) -> void:
	for _i: int in n:
		_tick()


func _tick() -> void:
	var t: int = grid.tick + 1
	for ev: Dictionary in _events:
		if int(ev["tick"]) != t:
			continue
		if ev["kind"] == "grid":
			grid.apply(ev["cmd"])  # break-only commands; the grid never refuses them
			_dirty = true
		elif ev["kind"] == "flood":
			var drain: String = _floods[ev["area"]].get("drained_by", "")
			if not (drain != "" and _latched.has(drain)):
				_water[ev["area"]] = int(ev["water_cm"])
	if not grid.step().is_empty():
		_dirty = true
	_refresh()
	for lid: String in _sorted(_latches.keys()):
		if _latched.has(lid):
			continue
		var la: Dictionary = _latches[lid]
		_latch_ticks[lid] = int(_latch_ticks[lid]) + 1 if _latch_ok[lid] else 0
		if int(_latch_ticks[lid]) >= int(la["supplied_ticks"]):
			_latched[lid] = t
			_grants[la["grants"]] = true
			for fid: String in _sorted(_floods.keys()):
				if _floods[fid].get("drained_by", "") == lid:
					_water[fid] = 0
	_verify_ticks = mini(_verify_ticks + 1, _need_verify) if _all_on else 0
	if solved_tick == UNSOLVED and verified() and stowed():
		solved_tick = t


# ---------- steps ----------

## Applies one trace step; returns "ok" or a refusal code. Every non-wait step then costs action_ticks.
func do_step(step: Dictionary) -> String:
	step = PowerGrid.json_ints(step)
	var kind: Variant = step.get("do")
	if kind == "wait":
		return _do_wait(step)
	var code: String
	match kind:
		"repair":
			code = _do_repair(step)
		"switch":
			code = _do_switch(step)
		"place":
			code = _do_place(step)
		"route":
			code = _do_route(step)
		"power":
			code = _do_power(step)
		"access":
			code = _do_access(step)
		_:
			return "BAD_STEP"
	advance(_action_ticks)
	return code


func _do_wait(step: Dictionary) -> String:
	var until: Variant = step.get("until")
	if until == null:
		var n: Variant = step.get("ticks")
		if not (n is int and int(n) >= 1):
			return "BAD_STEP"
		advance(int(n))
		return "ok"
	var check: Callable
	if until == "latch" and _latches.has(step.get("id")):
		check = func() -> bool: return _latched.has(step["id"])
	elif until == "verified":
		check = func() -> bool: return verified()
	elif until == "solved":
		check = func() -> bool: return solved_tick != UNSOLVED
	elif until == "tick" and step.get("tick") is int and int(step["tick"]) >= 1:
		check = func() -> bool: return grid.tick >= int(step["tick"])
	else:
		return "BAD_STEP"
	for _i: int in int(_rules["wait_limit_ticks"]):
		if check.call():
			return "ok"
		_tick()
	return "ok" if check.call() else "WAIT_TIMEOUT"


func _apply(cmd: Dictionary) -> String:
	var r: Dictionary = grid.apply(cmd)
	_dirty = true
	return "ok" if r["ok"] else str(r["code"])


func _grid_set(rid: String, field: String, value: bool) -> String:
	return _apply({"op": "set", "id": rid, "field": field, "value": value})


func _grid_field(rid: String, field: String) -> bool:
	var st: Dictionary = grid.canonical_state()
	var rec: Dictionary = st["nodes"][rid] if st["nodes"].has(rid) else st["edges"][rid]
	return rec[field]


func _do_repair(step: Dictionary) -> String:
	if not _faults.has(step.get("id")):
		return "UNKNOWN_ID"
	var f: Dictionary = _faults[step["id"]]
	var fid: String = f["id"]
	var j: String = f["junction"]
	if int(_fault_state[fid]) == 2:
		return "ALREADY_RESTORED"
	var access: String = f.get("access", "")
	if access != "" and not _held(access):
		return "ACCESS_BLOCKED"
	if int(_fault_state[fid]) == 0:
		var code: String = _grid_set(j, "isolated", true)
		if code != "ok":
			return code
		advance(_ceil_pct(int(f["work_ticks"]), _pct))
		code = _apply(f["fix"])
		if code != "ok":
			return code
		_fault_state[fid] = 1
	var was_isolated: bool = _grid_field(j, "isolated")
	var restore: String = _grid_set(j, "isolated", false)
	if restore != "ok":
		return restore
	if _grid_field(j, "tripped"):
		restore = _grid_set(j, "tripped", false)
		if restore != "ok":
			if was_isolated:
				_grid_set(j, "isolated", true)  # re-isolating only removes supply; keeps restore atomic
			return restore
	_fault_state[fid] = 2
	return "ok"


func _do_switch(step: Dictionary) -> String:
	if not _switches.has(step.get("id")):
		return "UNKNOWN_ID"
	var s: Dictionary = _switches[step["id"]]
	if not step.get("value") is bool:
		return "BAD_STEP"
	if _grid_field(s["target"], s["field"]) == step["value"]:
		return "NO_CHANGE"
	return _grid_set(s["target"], s["field"], step["value"])


func _do_place(step: Dictionary) -> String:
	if not _temps.has(step.get("id")):
		return "UNKNOWN_ID"
	var tid: String = step["id"]
	var a: Variant = step.get("anchor")
	if not (_anchors[tid] as Dictionary).has(a):
		return "UNKNOWN_ANCHOR"
	if a == _at[tid]:
		return "NO_CHANGE"
	if _grid_field(_temps[tid]["source"], "online"):
		return "SUPPLY_RUNNING"
	for e: String in _anchors[tid][_at[tid]]["routes"]:
		if _grid_field(e, "enabled"):
			return "ROUTES_CONNECTED"
	advance(_ceil_pct(int(_rules["carry_ticks"]), _pct))
	_at[tid] = a
	return "ok"


func _do_route(step: Dictionary) -> String:
	if not _temps.has(step.get("id")):
		return "UNKNOWN_ID"
	var tid: String = step["id"]
	var e: Variant = step.get("edge")
	var on: Variant = step.get("on")
	if not on is bool:
		return "BAD_STEP"
	if not (_anchors[tid][_at[tid]]["routes"] as Array).has(e):
		return "ROUTE_NOT_AT_ANCHOR"
	if _grid_field(e, "enabled") == on:
		return "NO_CHANGE"
	return _grid_set(e, "enabled", on)


func _do_power(step: Dictionary) -> String:
	if not _temps.has(step.get("id")):
		return "UNKNOWN_ID"
	var tid: String = step["id"]
	var on: Variant = step.get("on")
	if not on is bool:
		return "BAD_STEP"
	var src: String = _temps[tid]["source"]
	if _grid_field(src, "online") == on:
		return "NO_CHANGE"
	if on and _anchors[tid][_at[tid]]["storage"]:
		return "NOT_PLACED"
	return _grid_set(src, "online", on)


func _do_access(step: Dictionary) -> String:
	if not _routes.has(step.get("id")):
		return "UNKNOWN_ID"
	var r: Dictionary = _routes[step["id"]]
	var rid: String = r["id"]
	if _used_routes.has(rid):
		return "NO_CHANGE"
	var needs: String = r.get("requires_latch", "")
	if needs != "" and not _latched.has(needs):
		return "ACCESS_NOT_READY"
	if _route_closed(rid):
		return "ROUTE_CLOSED"
	_used_routes[rid] = true
	_grants[r["grants"]] = true
	return "ok"


# ---------- helpers ----------

static func _ceil_pct(ticks: int, pct: int) -> int:
	@warning_ignore("integer_division")
	return (ticks * pct + 99) / 100


static func _sorted(keys: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(keys)
	out.sort()
	return out
