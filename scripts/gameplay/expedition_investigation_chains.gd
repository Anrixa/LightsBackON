extends RefCounted
## EXP014 A08: host-authoritative, source-pinned nonlinear investigation graphs.
##
## Every one of 200 source cases has two explicit, independently authored
## evidence DAGs. A client may request only actions on real authenticated
## SC_* stations. Source authority, kit consumption, prerequisite edges,
## hazard health, elapsed ticks and certification are decided by the host.
##
## No new RPC, task IDs, credits, production saves or physical certification.

const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const BOOK_PATH: String = "res://scenes/expeditions/site_investigations_exp014_a08.json"
const MODES: Array[String] = ["forensic", "field"]
const GUARDS: Array[String] = [
	"faults_solved", "balancing_solved", "logistics_solved", "consequences_solved"
]
const MECHANICS: Array[String] = [
	"trace", "calibrate", "sample", "isolate", "crosscheck", "attest", "reconcile"
]

var _spec: Dictionary = {}
var _phase: String = "dormant"
var _mode: String = ""
var _route: String = ""
var _tick: int = 0
var _last_progress_tick: int = -1
var _kits: int = 3
var _liabilities: int = 0
var _fault: String = ""
var _failures: int = 0
var _recoveries: int = 0
var _completed: Dictionary = {}
var _solved: bool = false
var _history: Array[Dictionary] = []


static func _reject(code: String) -> Dictionary:
	return {"ok": false, "code": "EXP014_A08_" + code,
		"qualification": QUALIFICATION}


static func load_book() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(BOOK_PATH)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary or \
			parsed.get("schema_version") != 1 or \
			parsed.get("authority") != "EXP014_A08_HOST_INVESTIGATION_CHAINS" or \
			parsed.get("qualification") != QUALIFICATION or \
			not parsed.get("entries") is Array or parsed["entries"].size() != 200:
		return {}
	return parsed


static func entry_for(book: Dictionary, level_id: String) -> Dictionary:
	if not level_id.begins_with("LV_"):
		return {}
	var serial: int = int(level_id.trim_prefix("LV_"))
	if serial < 1 or serial > 200 or level_id != "LV_%03d" % serial:
		return {}
	var entries: Variant = book.get("entries")
	if not entries is Array or entries.size() != 200 or \
			not entries[serial - 1] is Dictionary:
		return {}
	var selected: Dictionary = entries[serial - 1]
	if selected.get("level_id") != level_id or \
			int(selected.get("case_serial", 0)) != serial:
		return {}
	return selected.duplicate(true)


## Source identity protects original catalog, case targets, route actions,
## immutable original job IDs and risk class. Graphs must be finite DAGs.
static func inspect(source: Dictionary, entry: Dictionary,
		hazard: Dictionary) -> Dictionary:
	if source.get("qualification") != QUALIFICATION or \
			entry.get("qualification", QUALIFICATION) != QUALIFICATION or \
			hazard.get("qualification") != QUALIFICATION:
		return _reject("UNQUALIFIED_SOURCE")
	for key: String in ["level_id", "location_id", "region_id",
			"source_risk", "source_task_ids", "targets",
			"source_puzzle_identity", "worksite_encounter_key",
			"source_route_actions"]:
		# The site A02 source is authoritative. A07's definition includes
		# only the common cross-phase subset, not source puzzle identity.
		if entry.get(key) != source.get(key):
			return _reject("SOURCE_SPLICE_" + key)
	for key: String in ["level_id", "location_id", "region_id",
			"source_risk", "source_task_ids", "targets", "risk_class"]:
		if entry.get(key) != hazard.get(key):
			return _reject("HAZARD_SOURCE_SPLICE_" + key)
	var level: String = str(entry.get("level_id", ""))
	var serial: int = int(level.trim_prefix("LV_")) if level.begins_with("LV_") else 0
	if serial < 1 or serial > 200 or level != "LV_%03d" % serial or \
			int(entry.get("case_serial", 0)) != serial or \
			str(entry.get("location_id", "")) != "LOC_%03d" % serial or \
			str(entry.get("region_id", "")) != "REG_%02d" % (int((serial - 1) / 8) + 1):
		return _reject("CATALOG_IDENTITY_DRIFT")
	var tasks: Variant = entry.get("source_task_ids")
	if not tasks is Array or tasks.size() != 5:
		return _reject("TASK_COVERAGE")
	for i: int in range(5):
		if str(tasks[i]) != "JOB_%03d_%d" % [serial, i + 1]:
			return _reject("TASK_ID_DRIFT")
	var targets: Variant = entry.get("targets")
	if not targets is Dictionary or targets.size() != 3 or \
			targets != source.get("targets") or \
			entry.get("recovery_target") != targets.get("C"):
		return _reject("TARGET_DRIFT")
	for letter: String in ["A", "B", "C"]:
		if targets.get(letter) != "SC_%03d_%s" % [serial, letter]:
			return _reject("SOURCE_TARGET_ID")
	var branches: Variant = entry.get("branches")
	if not branches is Dictionary or branches.size() != 2:
		return _reject("BRANCH_COVERAGE")
	for mode: String in MODES:
		if not branches.get(mode) is Dictionary:
			return _reject("MISSING_" + mode.to_upper())
		var branch: Dictionary = branches[mode]
		if not ["A", "B", "C"].has(str(branch.get("entry", ""))):
			return _reject("INVALID_ENTRY")
		var nodes: Variant = branch.get("nodes")
		var expected_count: int = 6 if mode == "forensic" else 7
		if not nodes is Array or nodes.size() != expected_count:
			return _reject("GRAPH_LENGTH")
		var seen: Dictionary = {}
		var total_cost: int = 0
		var source_actions: Variant = source["source_route_actions"][
			"priority" if mode == "forensic" else "resilience"]
		for n: int in range(expected_count):
			if not nodes[n] is Dictionary:
				return _reject("NODE_TYPE")
			var node: Dictionary = nodes[n]
			if node.size() != 8 or str(node.get("id", "")) != "P%d" % n or \
					not MECHANICS.has(str(node.get("kind", ""))) or \
					not ["A", "B", "C"].has(str(node.get("station", ""))) or \
					not GUARDS.has(str(node.get("guard", ""))) or \
					not source_actions.has(node.get("source_action")) or \
					not node.get("cost") is float and not node.get("cost") is int or \
					int(node.get("cost", -1)) < 0 or int(node.get("cost", -1)) > 1 or \
					int(node.get("dwell_ticks", 0)) < 2 or int(node.get("dwell_ticks", 0)) > 4:
				return _reject("NODE_SOURCE_INVALID")
			var requires: Variant = node.get("requires")
			if not requires is Array or \
					(n == 0 and not requires.is_empty()) or \
					(n > 0 and requires.is_empty()):
				return _reject("DEPENDENCY_COVERAGE")
			for dep: Variant in requires:
				if not seen.has(str(dep)):
					return _reject("NON_DAG_OR_FOREIGN_PREREQUISITE")
			seen[node["id"]] = true
			total_cost += int(node["cost"])
		if nodes[1]["requires"] != ["P0"] or nodes[2]["requires"] != ["P0"]:
			return _reject("MISSING_PARALLEL_INVESTIGATION")
		if str(nodes[expected_count - 1]["kind"]) != "attest":
			return _reject("MISSING_FINAL_ATTESTATION")
		if (mode == "forensic" and (total_cost < 1 or total_cost > 3)) or \
				(mode == "field" and total_cost != 0):
			return _reject("RESOURCE_MODEL_INVALID")
	return {"ok": true, "level_id": level, "investigation_branches": 2,
		"immutable_tasks": 5, "qualification": QUALIFICATION}


func configure(source: Dictionary, entry: Dictionary,
		hazard: Dictionary) -> Dictionary:
	if not _spec.is_empty():
		return _reject("ALREADY_CONFIGURED")
	var gate: Dictionary = inspect(source, entry, hazard)
	if not bool(gate.get("ok", false)):
		return gate
	_spec = entry.duplicate(true)
	return {"ok": true, "level_id": str(_spec["level_id"])}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


func target_ids() -> Array:
	return _spec.get("targets", {}).values()


func _target(letter: String) -> String:
	return str((_spec["targets"] as Dictionary)[letter])


func started() -> bool:
	return _phase != "dormant"


func solved() -> bool:
	return _solved


func needs_action() -> bool:
	return ["choose", "running", "fault"].has(_phase)


func _log(event: String) -> void:
	_history.append({"tick": _tick, "event": event, "phase": _phase})
	if _history.size() > 20:
		_history.pop_front()


## Hazard containment is proven by the existing host controller; a client
## snapshot cannot provide this because begin() is called by HostSession.
func begin(hazard: Dictionary) -> Dictionary:
	if _spec.is_empty() or started() or \
			hazard.get("qualification") != QUALIFICATION or \
			hazard.get("level_id") != _spec["level_id"] or \
			hazard.get("region_id") != _spec["region_id"] or \
			hazard.get("risk_class") != _spec["risk_class"] or \
			hazard.get("phase") != "contained" or \
			str(hazard.get("fault", "")) != "" or \
			not ["priority", "resilience"].has(str(hazard.get("route", ""))):
		return _reject("HAZARD_NOT_CONTAINED")
	_route = str(hazard["route"])
	_phase = "choose"
	_log("INVESTIGATION_OPENED")
	return {"ok": true, "state": snapshot()}


func _nodes() -> Array:
	if _mode == "" or _spec.is_empty():
		return []
	return (_spec["branches"][_mode] as Dictionary)["nodes"]


func _available() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if _phase != "running":
		return options
	for node: Dictionary in _nodes():
		if _completed.has(str(node["id"])):
			continue
		var unlocked: bool = true
		for prerequisite: Variant in node["requires"]:
			if not _completed.has(str(prerequisite)):
				unlocked = false
				break
		if unlocked:
			options.append({"id": node["id"], "kind": node["kind"],
				"source_action": node["source_action"],
				"target": _target(str(node["station"])),
				"action": "prove_%s_%s" % [str(node["id"]), str(node["kind"])],
				"guard": node["guard"], "cost": node["cost"],
				"dwell_ticks": node["dwell_ticks"]})
	return options


func snapshot() -> Dictionary:
	var choices: Array[Dictionary] = []
	if _phase == "choose":
		for mode: String in MODES:
			var branch: Dictionary = _spec["branches"][mode]
			choices.append({"mode": mode, "action": "begin_" + mode,
				"target": _target(str(branch["entry"])),
				"steps": (branch["nodes"] as Array).size()})
	var sources: Array[String] = []
	for node: Dictionary in _nodes():
		if _completed.has(str(node["id"])):
			sources.append(str(node["source_action"]))
	return {"level_id": str(_spec.get("level_id", "")),
		"region_id": str(_spec.get("region_id", "")),
		"risk_class": str(_spec.get("risk_class", "")),
		"phase": _phase, "mode": _mode, "route": _route, "tick": _tick,
		"kits": _kits, "liabilities": _liabilities,
		"completed": _completed.size(), "total": _nodes().size(),
		"observed_source_actions": sources,
		"choices": choices, "available": _available(),
		"fault": _fault, "failures": _failures, "recoveries": _recoveries,
		"recovery_target": _target("C") if not _spec.is_empty() else "",
		"solved": _solved, "history": _history.duplicate(true),
		"qualification": QUALIFICATION}


func _trip(reason: String) -> Dictionary:
	_fault = reason
	_phase = "fault"
	_failures += 1
	_liabilities = mini(12, _liabilities + 1)
	_log("INVESTIGATION_FAULT_" + reason)
	return _reject(reason)


func advance(facts: Dictionary) -> void:
	if not started() or _solved:
		return
	_tick += 1
	if _phase == "fault":
		return
	if not bool(facts.get("hazard_safe", false)):
		_trip("HAZARD_AUTHORITY_LOST")
		return
	if _phase == "running" and _last_progress_tick >= 0 and \
			_tick - _last_progress_tick > 70:
		_trip("EVIDENCE_STALE")


func operate(entity: String, action: String, facts: Dictionary) -> Dictionary:
	if _spec.is_empty() or not target_ids().has(entity):
		return _reject("UNKNOWN_SOURCE_STATION")
	if _phase == "dormant":
		return _reject("INVESTIGATION_NOT_STARTED")
	if _solved:
		return _reject("ALREADY_SOLVED")
	if _phase == "fault":
		if entity != _target("C") or action != "recover" or \
				not bool(facts.get("hazard_safe", false)) or \
				not bool(facts.get("worksite_opened", false)):
			return _reject("AUTHENTICATED_RECOVERY_REQUIRED")
		_recoveries += 1
		_fault = ""
		_completed.clear()
		_mode = ""
		_last_progress_tick = -1
		_phase = "choose"
		_log("REPLAY_AFTER_RECOVERY")
		return {"ok": true, "state": snapshot()}
	if not bool(facts.get("hazard_safe", false)) or \
			not bool(facts.get("worksite_opened", false)):
		return _trip("UPSTREAM_NOT_SAFE")
	if _phase == "choose":
		for mode: String in MODES:
			var branch: Dictionary = _spec["branches"][mode]
			if entity == _target(str(branch["entry"])) and action == "begin_" + mode:
				_mode = mode
				_phase = "running"
				_completed.clear()
				_last_progress_tick = -1
				if mode == "field":
					_liabilities = mini(12, _liabilities + 1)
				_log("EVIDENCE_PATH_" + mode.to_upper())
				return {"ok": true, "state": snapshot()}
		return _reject("INVALID_EVIDENCE_PATH")
	if _phase != "running":
		return _reject("INVALID_PHASE")
	if entity == _target("C") and action == "abandon":
		return _trip("OPERATOR_ABANDONED_EVIDENCE")
	for option: Dictionary in _available():
		if entity != str(option["target"]) or action != str(option["action"]):
			continue
		if not bool(facts.get(str(option["guard"]), false)):
			return _trip("UPSTREAM_PROOF_LOST")
		if int(option["cost"]) > _kits:
			return _reject("INSTRUMENT_KIT_EXHAUSTED")
		if _last_progress_tick >= 0 and \
				_tick - _last_progress_tick < int(option["dwell_ticks"]):
			return _reject("INDEPENDENT_EVIDENCE_NOT_SETTLED")
		_kits -= int(option["cost"])
		_completed[str(option["id"])] = true
		_last_progress_tick = _tick
		_log("HOST_PROOF_" + str(option["id"]))
		if _completed.size() == _nodes().size():
			if not bool(facts.get("hazard_safe", false)) or \
					str(facts.get("worksite_route", "")) != _route:
				return _trip("SOURCE_ROUTE_LOST")
			_solved = true
			_phase = "certified"
			_log("SITE_INVESTIGATION_CERTIFIED")
		return {"ok": true, "state": snapshot()}
	return _reject("INVALID_OR_LOCKED_EVIDENCE")
