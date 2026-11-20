extends RefCounted
## EXP014 A02: host-only post-intervention contingencies.
## All actions use the pre-existing authenticated, range-checked worksite ingress.
## Client clocks, phases, verdicts and source cases are never trusted.

const PATH: String = "res://scenes/expeditions/site_contingencies_exp014_a02.json"
const AUTHORITY: String = "EXP014_A02_HOST_CONTINGENCY"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const MODES: Array[String] = ["quorum", "reserve_lease", "isolation_mesh"]
const GUARDS: Array[String] = ["load_balanced", "supplies_ready", "cascade_stable", "fault_clear"]
const FAILURES: Array[String] = ["step", "backtrack", "restart"]
const ROUTES: Array[String] = ["priority", "resilience"]
const MAX_HISTORY: int = 48

var _spec: Dictionary = {}
var _route: String = ""
var _index: int = 0
var _tick: int = 0
var _phase: String = "ready"
var _start_tick: int = -1
var _deadline: int = -1
var _progress: int = 0
var _progress_tick: int = -1
var _fault: String = ""
var _failures: int = 0
var _recoveries: int = 0
var _unsafe_events: int = 0
var _started: bool = false
var _history: Array[Dictionary] = []


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return value if value is Dictionary else {}


static func _whole(value: Variant, low: float, high: float) -> bool:
	if not [TYPE_INT, TYPE_FLOAT].has(typeof(value)):
		return false
	var number: float = float(value)
	return is_finite(number) and number == float(int(number)) and number >= low and number <= high


static func _fingerprint(original: Dictionary, entry: Dictionary) -> String:
	var result: Array[String] = []
	for route: String in ROUTES:
		var old_steps: Array[String] = []
		for s: Dictionary in original["routes"][route]:
			old_steps.append("%s:%s:%s:%s" % [s["mode"], str(s["target"]).right(1),
				str(s["support_target"]).right(1), s["failure"]])
		var new_steps: Array[String] = []
		for s: Dictionary in entry["routes"][route]:
			new_steps.append("%s:%s:%s:%s:%s:%s" % [s["mode"],
				str(s["target"]).right(1), str(s["support"]).right(1),
				str(s["witness"]).right(1), s["guard"], s["failure"]])
		result.append("|".join(old_steps) + "#" + "|".join(new_steps))
	return "~".join(result)


## The old source has already passed its EXP012/EXP013 independent audit.
## This additional gate pins all inherited identities, route actions, tasks,
## source control targets, mechanics and the honest noncosmetic diversity floor.
static func inspect(atlas: Dictionary, old_cases: Array[Dictionary],
		book: Dictionary) -> Dictionary:
	if book.get("schema_version") != 1 or book.get("authority") != AUTHORITY or \
			book.get("qualification") != QUALIFICATION or \
			book.get("atlas_revision") != atlas.get("revision"):
		return {"ok": false, "code": "EXP014_BOOK_HEADER"}
	var records: Variant = book.get("entries")
	if not records is Array or records.size() != 200 or \
			old_cases.size() != 200 or atlas.get("levels", []).size() != 200:
		return {"ok": false, "code": "EXP014_BOOK_COVERAGE"}
	var structures: Dictionary = {}
	var regions: Dictionary = {}
	for n: int in range(200):
		if not records[n] is Dictionary:
			return {"ok": false, "code": "EXP014_ENTRY_TYPE", "index": n}
		var e: Dictionary = records[n]
		var old: Dictionary = old_cases[n]
		var level: Dictionary = atlas["levels"][n]
		for key: String in ["level_id", "location_id", "region_id", "source_title",
				"source_risk", "source_climate", "source_puzzle_identity",
				"source_task_ids", "worksite_encounter_key", "targets",
				"recovery_target", "qualification"]:
			if e.get(key) != old.get(key):
				return {"ok": false, "code": "EXP014_SOURCE_DRIFT_" + key, "index": n}
		if e.get("level_id") != level.get("id") or \
				e.get("source_task_ids") != [
					level["tasks"][0]["id"], level["tasks"][1]["id"],
					level["tasks"][2]["id"], level["tasks"][3]["id"],
					level["tasks"][4]["id"]]:
			return {"ok": false, "code": "EXP014_TASK_DRIFT", "index": n}
		if e.get("intervention_title") != old.get("title") or \
				e.get("stakes") != old.get("stakes"):
			return {"ok": false, "code": "EXP014_STAKES_DRIFT", "index": n}
		var routes: Variant = e.get("routes")
		var original_actions: Variant = e.get("source_route_actions")
		if not routes is Dictionary or routes.size() != 2 or \
				not original_actions is Dictionary or \
				not GUARDS.has(str(e.get("risk_guard", ""))):
			return {"ok": false, "code": "EXP014_ROUTE_BOOK", "index": n}
		var targets: Array = old["targets"].values()
		for route: String in ROUTES:
			var valid_actions: Array[String] = []
			for old_step: Dictionary in old["routes"][route]:
				valid_actions.append(str(old_step["action"]))
			if original_actions.get(route) != valid_actions:
				return {"ok": false, "code": "EXP014_ACTION_PIN", "index": n}
			var steps: Variant = routes.get(route)
			if not steps is Array or steps.size() != 3:
				return {"ok": false, "code": "EXP014_STEP_COUNT", "index": n}
			for value: Variant in steps:
				if not value is Dictionary:
					return {"ok": false, "code": "EXP014_STEP_TYPE", "index": n}
				var step: Dictionary = value
				if step.size() != 10 or \
						not MODES.has(str(step.get("mode", ""))) or \
						not GUARDS.has(str(step.get("guard", ""))) or \
						not FAILURES.has(str(step.get("failure", ""))) or \
						not targets.has(step.get("target")) or \
						not targets.has(step.get("support")) or \
						not targets.has(step.get("witness")) or \
						step.get("target") == step.get("support") or \
						step.get("target") == step.get("witness") or \
						step.get("support") == step.get("witness"):
					return {"ok": false, "code": "EXP014_STEP_TOPOLOGY", "index": n}
				if not _whole(step.get("dwell_ticks"), 6.0, 24.0) or \
						not _whole(step.get("window_ticks"), 40.0, 240.0) or \
						not _whole(step.get("witness_gap_ticks"), 3.0, 8.0):
					return {"ok": false, "code": "EXP014_HOST_TIMER", "index": n}
				var action: String = str(step.get("action", ""))
				if not action.begins_with("contingency_") or \
						not valid_actions.has(action.trim_prefix("contingency_")) or \
						not action.is_valid_identifier():
					return {"ok": false, "code": "EXP014_UNBOUND_ACTION", "index": n}
		var sig: String = _fingerprint(old, e)
		structures[sig] = int(structures.get(sig, 0)) + 1
		regions[str(e["region_id"])] = true
	var max_reuse: int = 0
	for count: Variant in structures.values():
		max_reuse = maxi(max_reuse, int(count))
	if structures.size() < 150 or max_reuse > 8 or regions.size() != 25:
		return {"ok": false, "code": "EXP014_DIVERSITY_REGRESSION",
			"distinct": structures.size(), "max_reuse": max_reuse}
	return {"ok": true, "cases": 200, "routes": 400,
		"steps": 1200, "distinct": structures.size(),
		"max_reuse": max_reuse, "regions": 25,
		"qualification": QUALIFICATION}


static func entry_for(book: Dictionary, id: String) -> Dictionary:
	for raw: Variant in book.get("entries", []):
		if raw is Dictionary and raw.get("level_id") == id:
			return (raw as Dictionary).duplicate(true)
	return {}


func configure(entry: Dictionary) -> Dictionary:
	if not _spec.is_empty() or not entry.get("routes") is Dictionary or \
			not entry.get("targets") is Dictionary:
		return {"ok": false, "code": "EXP014_CONFIG_INVALID"}
	_spec = entry.duplicate(true)
	return {"ok": true}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


func target_ids() -> Array[String]:
	var result: Array[String] = []
	for value: Variant in _spec.get("targets", {}).values():
		result.append(str(value))
	return result


func can_choose_route(route: String) -> bool:
	return ROUTES.has(route) and (_route == "" or _route == route or \
		(not _started and _index == 0 and _fault == ""))


func choose_route(route: String) -> Dictionary:
	if not can_choose_route(route):
		return {"ok": false, "code": "EXP014_ROUTE_LOCKED"}
	_route = route
	_log("HOST_ROUTE_BOUND", str(_spec.get("level_id", "")))
	return {"ok": true, "route": _route}


func _current() -> Dictionary:
	if _spec.is_empty() or _route == "" or _index >= 3:
		return {}
	return _spec["routes"][_route][_index]


func _upstream_safe(facts: Dictionary) -> bool:
	return bool(facts.get("site_intervention_solved", false)) and \
		bool(facts.get("worksite_opened", false)) and \
		bool(facts.get("balancing_solved", false)) and \
		bool(facts.get("logistics_solved", false)) and \
		bool(facts.get("consequences_solved", false)) and \
		bool(facts.get("faults_solved", false)) and \
		bool(facts.get("west_restored", false)) and \
		bool(facts.get("east_on", false)) and \
		not bool(facts.get("hazard_active", true)) and \
		str(facts.get("worksite_route", "")) == _route


func _guard_safe(facts: Dictionary, guard: String) -> bool:
	match guard:
		"load_balanced":
			return bool(facts.get("balancing_solved", false))
		"supplies_ready":
			return bool(facts.get("logistics_solved", false))
		"cascade_stable":
			return bool(facts.get("consequences_solved", false))
		"fault_clear":
			return bool(facts.get("faults_solved", false)) and \
				not bool(facts.get("hazard_active", true))
	return false


func _log(event: String, station: String) -> void:
	_history.append({"tick": _tick, "event": event, "station": station,
		"step": _index, "route": _route})
	while _history.size() > MAX_HISTORY:
		_history.pop_front()


func _reset_step() -> void:
	_phase = "ready"
	_start_tick = -1
	_deadline = -1
	_progress = 0
	_progress_tick = -1


func _break(reason: String, scope: String) -> Dictionary:
	_failures += 1
	_started = true
	if scope == "restart":
		_index = 0
	elif scope == "backtrack":
		_index = maxi(0, _index - 1)
	_reset_step()
	_fault = reason
	_log("FAULT_" + reason, str(_spec.get("recovery_target", "")))
	return {"ok": false, "code": "EXP014_" + reason,
		"needs_recovery": true, "step": _index}


func _finish_step() -> Dictionary:
	var step: Dictionary = _current()
	_log("COMPLETED_" + str(step["mode"]).to_upper(), str(step["target"]))
	_index += 1
	_reset_step()
	if _index == 3:
		_phase = "done"
		_log("CONTINGENCY_CERTIFIED", str(_spec["recovery_target"]))
	return {"ok": true, "step": _index, "solved": solved()}


func solved() -> bool:
	return not _spec.is_empty() and _route != "" and _index == 3 and _fault == ""


func operate(entity: String, action: String, facts: Dictionary) -> Dictionary:
	if not target_ids().has(entity):
		return {"ok": false, "code": "EXP014_UNKNOWN_TARGET"}
	if _route == "":
		return {"ok": false, "code": "EXP014_ROUTE_NOT_BOUND"}
	if not _upstream_safe(facts):
		return {"ok": false, "code": "EXP014_UPSTREAM_INTERLOCK"}
	if _fault != "":
		if entity != str(_spec["recovery_target"]) or action != "recover":
			return {"ok": false, "code": "EXP014_RECOVERY_REQUIRED"}
		_fault = ""
		_recoveries += 1
		_log("RECOVERED", entity)
		return {"ok": true, "recovered": true, "step": _index}
	if solved():
		return {"ok": false, "code": "EXP014_ALREADY_CERTIFIED"}
	var step: Dictionary = _current()
	if not _guard_safe(facts, str(step["guard"])):
		return {"ok": false, "code": "EXP014_SERVICE_GUARD"}
	var target: String = str(step["target"])
	var support: String = str(step["support"])
	var witness: String = str(step["witness"])
	var mode: String = str(step["mode"])
	if _phase == "ready":
		if entity != target or action != str(step["action"]):
			return {"ok": false, "code": "EXP014_ORDER_REQUIRED"}
		_started = true
		_phase = "warming"
		_start_tick = _tick
		_log("BEGIN_" + mode.to_upper(), entity)
		return {"ok": true, "warming": true, "step": _index}
	if _phase == "warming":
		if entity == target and ["seal", "release", "close"].has(action):
			return _break("PREMATURE_CLOSE", str(step["failure"]))
		return {"ok": false, "code": "EXP014_WAIT_HOST_DWELL"}
	if _phase != "stable":
		return {"ok": false, "code": "EXP014_INVALID_PHASE"}
	if _tick > _deadline:
		return _break("WINDOW_EXPIRED", str(step["failure"]))
	if _progress == 0:
		var first_action: String = "read" if mode == "quorum" else \
			"arm" if mode == "reserve_lease" else "isolate"
		if entity != support or action != first_action:
			return {"ok": false, "code": "EXP014_FIRST_STATION_REQUIRED"}
		_progress = 1
		_progress_tick = _tick
		_log("SUPPORT_" + first_action.to_upper(), entity)
		return {"ok": true, "progress": 1}
	if _progress == 1:
		var second_action: String = "attest" if mode == "quorum" else \
			"transfer" if mode == "reserve_lease" else "verify"
		if entity != witness or action != second_action:
			return {"ok": false, "code": "EXP014_WITNESS_REQUIRED"}
		if _tick - _progress_tick < int(step["witness_gap_ticks"]):
			return {"ok": false, "code": "EXP014_WITNESS_GAP_REQUIRED"}
		_progress = 2
		_progress_tick = _tick
		_log("WITNESS_" + second_action.to_upper(), entity)
		return {"ok": true, "progress": 2}
	var final_action: String = "seal" if mode == "quorum" else \
		"release" if mode == "reserve_lease" else "close"
	if entity != target or action != final_action:
		return {"ok": false, "code": "EXP014_FINAL_TARGET_REQUIRED"}
	var settle: int = 2 if mode == "quorum" else \
		4 if mode == "reserve_lease" else 3
	if _tick - _progress_tick < settle:
		return {"ok": false, "code": "EXP014_SETTLING_REQUIRED"}
	return _finish_step()


func advance(facts: Dictionary) -> void:
	if _spec.is_empty() or _route == "":
		return
	if not bool(facts.get("site_intervention_solved", false)) and not _started:
		return
	if not _upstream_safe(facts):
		if _fault == "" and _started:
			_unsafe_events += 1
			_break("SUPPLY_LOST", "restart")
		return
	if solved() or _fault != "":
		return
	_tick += 1
	if _phase == "warming":
		var step: Dictionary = _current()
		if _tick - _start_tick >= int(step["dwell_ticks"]):
			_phase = "stable"
			_deadline = _tick + int(step["window_ticks"])
			_log("HOST_STABLE", str(step["target"]))
	elif _phase == "stable" and _tick > _deadline:
		_break("WINDOW_EXPIRED", str(_current()["failure"]))


func snapshot() -> Dictionary:
	return {"ok": not _spec.is_empty(), "level_id": _spec.get("level_id", ""),
		"route": _route, "step": _index, "step_count": 3, "phase": _phase,
		"fault": _fault, "tick": _tick, "start_tick": _start_tick,
		"deadline": _deadline, "progress": _progress,
		"progress_tick": _progress_tick, "started": _started,
		"recoveries": _recoveries, "failures": _failures,
		"unsafe_events": _unsafe_events, "solved": solved(),
		"next": _current().duplicate(true),
		"recovery_target": _spec.get("recovery_target", ""),
		"qualification": QUALIFICATION, "history": _history.duplicate(true)}
