extends RefCounted
## EXP009 — Opt-in, host-owned cascading service consequences.
## Failure spreads through source-authored dependencies on fixed SessionHost
## ticks. Client intents can survey or request a response, never set exposure,
## grid state, failure history, host time, consequence score or completion.

const BOOK_PATH: String = "res://scenes/expeditions/consequence_chains.json"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const SAFE_STATES: Array[String] = ["isolated", "diverted", "restored"]
const ANCHORS: Array[String] = ["PANEL_WEST", "PANEL_SPUR", "R_WEST"]
const MAX_EVENTS: int = 24

var _spec: Dictionary = {}
var _nodes: Dictionary = {}
var _clock: int = 0
var _started: bool = false
var _certified: bool = false
var _reserve: int = 0
var _failures: int = 0
var _recoveries: int = 0
var _diversions: int = 0
var _reopens: int = 0
var _history: Array[Dictionary] = []


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return decoded if decoded is Dictionary else {}


static func entry_for(book: Dictionary, level: Dictionary, fault: Dictionary) -> Dictionary:
	for raw: Variant in book.get("entries", []):
		if not raw is Dictionary:
			return {}
		var entry: Dictionary = raw
		if entry.get("level_id") != level.get("id"):
			continue
		for name: String in ["location_id", "source_puzzle_identity"]:
			var expected: Variant = level.get("location_id") if name == "location_id" else level.get("puzzle_identity")
			if entry.get(name) != expected:
				return {}
		for name: String in ["scenario_key", "graph_key", "fault_class", "site"]:
			if entry.get(name) != fault.get(name):
				return {}
		return entry.duplicate(true)
	return {}


## Independently inspect EVERY source key and the entire acyclic propagation DAG.
## A foreign, duplicated, cyclic, unbounded, or silently swapped profile fails.
static func inspect(atlas: Dictionary, faults: Dictionary, book: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if book.get("schema_version") != 1 or \
			book.get("authority") != "EXP009_HOST_CONSEQUENCES" or \
			book.get("atlas_revision") != atlas.get("revision"):
		errors.append("HEADER_INVALID")
	var entries: Variant = book.get("entries")
	if not entries is Array or (entries as Array).size() != 200:
		return {"ok": false, "code": "EXP009_COUNT_INVALID", "failures": errors}
	var levels: Dictionary = {}
	for level: Dictionary in atlas.get("levels", []):
		levels[str(level.get("id", ""))] = level
	var fault_records: Dictionary = {}
	for fault: Dictionary in faults.get("entries", []):
		fault_records[str(fault.get("level_id", ""))] = fault
	var seen: Dictionary = {}
	var keys: Dictionary = {}
	var shapes: Dictionary = {}
	for raw: Variant in entries:
		if not raw is Dictionary:
			errors.append("ENTRY_NOT_OBJECT")
			continue
		var entry: Dictionary = raw
		var lid: String = str(entry.get("level_id", ""))
		if seen.has(lid) or not levels.has(lid) or not fault_records.has(lid):
			errors.append("FOREIGN_OR_DUPLICATE_" + lid)
			continue
		seen[lid] = true
		if entry_for({"entries": [entry]}, levels[lid], fault_records[lid]).is_empty():
			errors.append("SOURCE_DRIFT_" + lid)
		var key: String = str(entry.get("chain_key", ""))
		if key != str(entry.get("scenario_key", "")) + "|EXP009|" + str(entry.get("topology", "")) or keys.has(key):
			errors.append("KEY_INVALID_" + lid)
		keys[key] = true
		if not ["serial", "fork"].has(entry.get("topology")):
			errors.append("TOPOLOGY_INVALID_" + lid)
		else:
			shapes[str(entry["topology"])] = true
		if entry.get("reserve") != 1 or entry.get("console") != "FC_%s_CTRL" % lid.trim_prefix("LV_") or \
				entry.get("console_anchor") != "R_WEST":
			errors.append("CONSOLE_INVALID_" + lid)
		var nodes: Variant = entry.get("nodes")
		if not nodes is Array or (nodes as Array).size() != 3:
			errors.append("NODES_INVALID_" + lid)
			continue
		var local: Dictionary = {}
		for index: int in range(3):
			if not nodes[index] is Dictionary:
				errors.append("NODE_NOT_OBJECT_" + lid)
				continue
			var node: Dictionary = nodes[index]
			var id: String = str(node.get("id", ""))
			var expected_parent: String = "" if index == 0 else \
				str(nodes[0].get("id", "")) if entry.get("topology") == "fork" else \
				str(nodes[index - 1].get("id", ""))
			if id != "FC_%s_%d" % [lid.trim_prefix("LV_"), index] or local.has(id) or \
					node.get("parent") != expected_parent or \
					node.get("anchor") != ANCHORS[index] or \
					not node.get("service") is String or str(node.get("service", "")).length() < 4 or \
					not node.get("impact") is String or str(node.get("impact", "")).length() < 5:
				errors.append("NODE_SOURCE_OR_TOPOLOGY_INVALID_" + lid)
			local[id] = true
			var limit: Variant = node.get("threshold_ticks")
			if not (limit is int or limit is float) or int(limit) < 12 or int(limit) > 40 or \
					float(limit) != float(int(limit)):
				errors.append("THRESHOLD_INVALID_" + lid)
	if seen.size() != 200 or keys.size() != 200 or shapes.size() != 2:
		errors.append("COVERAGE_INVALID")
	return {"ok": errors.is_empty(), "code": "OK" if errors.is_empty() else "EXP009_INVALID",
		"levels": seen.size(), "topologies": shapes.size(), "nodes": seen.size() * 3,
		"failures": errors}


func configure(entry: Dictionary) -> Dictionary:
	if not _spec.is_empty() or not entry.has("chain_key") or \
			not entry.get("nodes") is Array or (entry["nodes"] as Array).size() != 3:
		return {"ok": false, "code": "EXP009_CONFIG_INVALID"}
	_spec = entry.duplicate(true)
	_reserve = int(entry.get("reserve", 0))
	for node: Dictionary in entry["nodes"]:
		_nodes[str(node["id"])] = {"status": "dormant", "exposure": 0, "surveyed": false}
	return {"ok": true}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


func target_ids() -> Array[String]:
	var ids: Array[String] = []
	if _spec.is_empty():
		return ids
	for node: Dictionary in _spec["nodes"]:
		ids.append(str(node["id"]))
	ids.append(str(_spec["console"]))
	return ids


func _record(action: String, id: String) -> void:
	_history.append({"tick": _clock, "event": action, "node": id})
	while _history.size() > MAX_EVENTS:
		_history.pop_front()


func _activate_children(parent_id: String) -> void:
	for node: Dictionary in _spec["nodes"]:
		if node.get("parent") == parent_id:
			var id: String = str(node["id"])
			if str(_nodes[id]["status"]) == "dormant":
				_nodes[id]["status"] = "at_risk"
				_record("EXPOSURE_STARTED", id)


func _host_ready(facts: Dictionary) -> bool:
	return bool(facts.get("west_inspected", false)) and \
			bool(facts.get("devices_solved", false)) and \
			bool(facts.get("west_restored", false)) and \
			bool(facts.get("east_on", false)) and \
			not bool(facts.get("hazard_active", true))


func _node_def(id: String) -> Dictionary:
	for item: Dictionary in _spec.get("nodes", []):
		if item.get("id") == id:
			return item
	return {}


func _ancestor_safe(node: Dictionary) -> bool:
	var parent: String = str(node.get("parent", ""))
	return parent == "" or (_nodes.has(parent) and SAFE_STATES.has(_nodes[parent]["status"]))


func _resolved() -> bool:
	if _nodes.size() != 3:
		return false
	for id: String in _nodes:
		if not SAFE_STATES.has(_nodes[id]["status"]):
			return false
	return true


## Called only after a validated nonduplicate SessionHost envelope AND range/LoS.
func operate(id: String, action: String, facts: Dictionary) -> Dictionary:
	if _spec.is_empty():
		return {"ok": false, "code": "EXP009_NOT_CONFIGURED"}
	if id == str(_spec["console"]):
		if action != "certify":
			return {"ok": false, "code": "EXP009_CONSOLE_ACTION_INVALID"}
		if not _started or not _resolved() or \
				not bool(facts.get("faults_solved", false)) or not _host_ready(facts):
			return {"ok": false, "code": "EXP009_CASCADE_UNRESOLVED"}
		_certified = true
		_record("SERVICE_CERTIFIED", id)
		return {"ok": true, "certified": true, "impact_count": _failures}
	if not _nodes.has(id):
		return {"ok": false, "code": "EXP009_UNKNOWN_TARGET"}
	if not _started:
		return {"ok": false, "code": "EXP009_FAULT_DIAGNOSIS_REQUIRED"}
	var status: String = str(_nodes[id]["status"])
	if action == "survey":
		if status == "dormant" or bool(_nodes[id]["surveyed"]):
			return {"ok": false, "code": "EXP009_SURVEY_UNAVAILABLE"}
		_nodes[id]["surveyed"] = true
		_record("SERVICE_SURVEYED", id)
		return {"ok": true, "status": status, "service": _node_def(id)["service"]}
	if not bool(_nodes[id]["surveyed"]):
		return {"ok": false, "code": "EXP009_SURVEY_REQUIRED"}
	var node: Dictionary = _node_def(id)
	if action == "repair":
		if status != "failed" or not _ancestor_safe(node) or \
				not _host_ready(facts) or bool(facts.get("spur_on", true)):
			return {"ok": false, "code": "EXP009_REPAIR_INTERLOCK"}
		_nodes[id]["status"] = "restored"
		_recoveries += 1
		_record("SERVICE_RESTORED", id)
		_activate_children(id)
		return {"ok": true, "status": "restored"}
	if status != "at_risk" or not _ancestor_safe(node) or not _host_ready(facts):
		return {"ok": false, "code": "EXP009_UPSTREAM_OR_HOST_INTERLOCK"}
	if action == "isolate":
		if bool(facts.get("spur_on", true)):
			return {"ok": false, "code": "EXP009_SPUR_MUST_BE_OFF"}
		_nodes[id]["status"] = "isolated"
	elif action == "divert":
		if not bool(facts.get("spur_on", false)) or _reserve == 0:
			return {"ok": false, "code": "EXP009_DIVERSION_UNAVAILABLE"}
		_reserve -= 1
		_diversions += 1
		_nodes[id]["status"] = "diverted"
	else:
		return {"ok": false, "code": "EXP009_ACTION_INVALID"}
	_record("SERVICE_" + str(_nodes[id]["status"]).to_upper(), id)
	_activate_children(id)
	return {"ok": true, "status": _nodes[id]["status"], "reserve": _reserve}


## Runs on the same fixed host tick as EXP08, never a client or wall clock.
func advance(facts: Dictionary) -> void:
	if _spec.is_empty():
		return
	_clock += 1
	if not _started:
		if ["route", "prepared", "holding", "verified", "faulted", "complete"].has(str(facts.get("fault_phase", ""))):
			_started = true
			var root: String = str(_spec["nodes"][0]["id"])
			_nodes[root]["status"] = "at_risk"
			_record("CASCADE_STARTED", root)
		else:
			return
	if _certified:
		if not _host_ready(facts) or not bool(facts.get("faults_solved", false)):
			_certified = false
			_reopens += 1
			var root: String = str(_spec["nodes"][0]["id"])
			_nodes[root]["status"] = "at_risk"
			_nodes[root]["exposure"] = 0
			_record("SERVICE_REOPENED", root)
		return
	for node: Dictionary in _spec["nodes"]:
		var id: String = str(node["id"])
		if str(_nodes[id]["status"]) != "at_risk":
			continue
		# Host-only pressure: failing electrical or hazard evidence accelerates
		# the countdown, and a failed upstream service spreads pressure.
		var weight: int = 1
		if not _host_ready(facts) or str(facts.get("fault_phase", "")) == "faulted":
			weight += 1
		var parent: String = str(node["parent"])
		if parent != "" and _nodes.has(parent) and _nodes[parent]["status"] == "failed":
			weight += 1
		_nodes[id]["exposure"] = int(_nodes[id]["exposure"]) + weight
		if int(_nodes[id]["exposure"]) >= int(node["threshold_ticks"]):
			_nodes[id]["status"] = "failed"
			_failures += 1
			_record("SERVICE_FAILED:" + str(node["impact"]), id)
			_activate_children(id)


func solved() -> bool:
	return _certified and _resolved() and not _spec.is_empty()


func snapshot() -> Dictionary:
	return {"ok": not _spec.is_empty(), "level_id": _spec.get("level_id", ""),
		"chain_key": _spec.get("chain_key", ""), "started": _started,
		"certified": _certified, "solved": solved(), "tick": _clock,
		"states": _nodes.duplicate(true), "reserve": _reserve,
		"failures": _failures, "recoveries": _recoveries,
		"diversions": _diversions, "reopens": _reopens,
		"history": _history.duplicate(true), "qualification": QUALIFICATION}
