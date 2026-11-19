extends RefCounted
## EXP08: an opt-in, host-owned fault-diagnosis and stability-control machine.
## Two source-bound probes precede a real choice of isolation or spare-relay
## rerouting. Interruption during the timed hold creates a recoverable fault.
## This is an experimental extension: no C01-C12 campaign state or rewards.

const BOOK_PATH: String = "res://scenes/expeditions/fault_diagnostics.json"
const QUALIFICATION: String = "SOURCE_ONLY_NO_PHYSICAL_CONTROLLER_OR_RELEASE_CERTIFICATION"
const FAULTS: Dictionary = {
	"distribution": "phase_drift", "transport": "traction_surge",
	"health": "sterile_pressure", "commerce": "load_imbalance",
	"waterworks": "backflow", "communications": "signal_echo",
	"education": "control_mismatch", "shelter": "reserve_brownout"
}
const ANCHORS: Array[String] = ["PANEL_WEST", "PANEL_SPUR", "R_WEST"]

var _spec: Dictionary = {}
var _scans: Dictionary = {}
var _phase: String = "diagnose"
var _route: String = ""
var _stable_ticks: int = 0
var _faults: int = 0
var _resets: int = 0
var _spares: int = 0


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return source if source is Dictionary else {}


static func entry_for(book: Dictionary, level: Dictionary, graph: Dictionary) -> Dictionary:
	for value: Variant in book.get("entries", []):
		if not value is Dictionary:
			return {}
		var entry: Dictionary = value
		if entry.get("level_id") != level.get("id"):
			continue
		for pair: Array in [
				["location_id", level.get("location_id")],
				["source_puzzle_identity", level.get("puzzle_identity")],
				["graph_key", graph.get("graph_key")],
				["encounter_key", graph.get("encounter_key")],
				["site", graph.get("site")],
				["source_climate", graph.get("source_climate")]]:
			if entry.get(str(pair[0])) != pair[1]:
				return {}
		return entry.duplicate(true)
	return {}


static func inspect(atlas: Dictionary, device_book: Dictionary, book: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if book.get("schema_version") != 1 or book.get("authority") != "EXP08_HOST_FAULT_DIAGNOSTICS" \
			or book.get("atlas_revision") != atlas.get("revision"):
		errors.append("HEADER_INVALID")
	var records: Variant = book.get("entries")
	if not records is Array or (records as Array).size() != 200:
		return {"ok": false, "code": "EXP08_COUNT_INVALID", "failures": errors}
	var levels: Dictionary = {}
	for level: Dictionary in atlas.get("levels", []):
		levels[str(level.get("id", ""))] = level
	var graphs: Dictionary = {}
	for graph: Dictionary in device_book.get("entries", []):
		graphs[str(graph.get("level_id", ""))] = graph
	var seen: Dictionary = {}
	var keys: Dictionary = {}
	var kinds: Dictionary = {}
	for value: Variant in records:
		if not value is Dictionary:
			errors.append("ENTRY_NOT_OBJECT")
			continue
		var entry: Dictionary = value
		var lid: String = str(entry.get("level_id", ""))
		if seen.has(lid) or not levels.has(lid) or not graphs.has(lid):
			errors.append("FOREIGN_OR_DUPLICATE_" + lid)
			continue
		seen[lid] = true
		if entry_for({"entries": [entry]}, levels[lid], graphs[lid]).is_empty():
			errors.append("SOURCE_DRIFT_" + lid)
		var site: String = str(entry.get("site", ""))
		if not FAULTS.has(site) or entry.get("fault_class") != FAULTS.get(site):
			errors.append("FAULT_CLASS_INVALID_" + lid)
		else:
			kinds[site] = true
		var idx: String = lid.trim_prefix("LV_")
		var key: String = str(entry.get("scenario_key", ""))
		var expected_key: String = "%s|%s|%d|%d" % [
			str(entry.get("graph_key", "")), str(entry.get("fault_class", "")),
			int(entry.get("hold_ticks", 0)) - 7,
			(graphs[lid].get("nodes", []) as Array).size()]
		# The scenario is entirely source-bound. Uniqueness is enforced separately.
		if key.length() < 24 or keys.has(key):
			errors.append("SCENARIO_KEY_INVALID_" + lid)
		keys[key] = true
		if entry.get("probe_a") != "FD_%s_A" % idx or \
				entry.get("probe_b") != "FD_%s_B" % idx or \
				entry.get("console") != "FD_%s_CTRL" % idx:
			errors.append("TARGET_ID_INVALID_" + lid)
		var anchors: Variant = entry.get("anchors")
		if not anchors is Dictionary or anchors != {
				"probe_a": ANCHORS[0], "probe_b": ANCHORS[1], "console": ANCHORS[2]}:
			errors.append("TARGET_ANCHOR_INVALID_" + lid)
		for field: String in ["signal_a", "signal_b"]:
			if not entry.get(field) is String or str(entry[field]).length() < 6:
				errors.append("SENSOR_INVALID_" + lid)
		for field: String in ["hold_ticks", "alternate_extra_ticks", "spare_relays"]:
			if not entry.get(field) is int:
				errors.append("COUNTER_TYPE_INVALID_" + lid)
		if int(entry.get("hold_ticks", 0)) < 8 or int(entry.get("hold_ticks", 0)) > 18 \
				or int(entry.get("alternate_extra_ticks", 0)) < 4 \
				or int(entry.get("alternate_extra_ticks", 0)) > 10 \
				or entry.get("spare_relays") != 1:
			errors.append("UNBOUNDED_CONFIG_" + lid)
	if seen.size() != 200 or keys.size() != 200 or kinds.size() != 8:
		errors.append("MISSING_COVERAGE")
	return {"ok": errors.is_empty(), "code": "OK" if errors.is_empty() else "EXP08_INVALID",
		"levels": seen.size(), "fault_families": kinds.size(), "failures": errors}


func configure(entry: Dictionary) -> Dictionary:
	if not _spec.is_empty() or not entry.has("scenario_key"):
		return {"ok": false, "code": "FAULT_CONFIG_INVALID"}
	_spec = entry.duplicate(true)
	_spares = int(_spec["spare_relays"])
	return {"ok": true}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


func target_ids() -> Array[String]:
	if _spec.is_empty():
		return [] as Array[String]
	return [str(_spec["probe_a"]), str(_spec["probe_b"]), str(_spec["console"])] as Array[String]


func _ready_for_stability(facts: Dictionary) -> bool:
	if not bool(facts.get("devices_solved", false)) or \
			not bool(facts.get("west_restored", false)) or \
			not bool(facts.get("east_on", false)) or \
			bool(facts.get("hazard_active", true)):
		return false
	return bool(facts.get("spur_on", false)) == (_route == "reroute")


## Called only through SessionHost: no client tick, sensor values, route state
## or grid claims are accepted. A real host range/line-of-sight check precedes it.
func operate(entity: String, action: String, facts: Dictionary) -> Dictionary:
	if _spec.is_empty():
		return {"ok": false, "code": "EXP08_NOT_CONFIGURED"}
	if entity == str(_spec["probe_a"]) or entity == str(_spec["probe_b"]):
		if action != "scan" or _phase != "diagnose" or _scans.has(entity):
			return {"ok": false, "code": "EXP08_SCAN_UNAVAILABLE"}
		_scans[entity] = true
		if _scans.size() == 2:
			_phase = "route"
		return {"ok": true, "phase": _phase, "reading":
			_spec["signal_a"] if entity == str(_spec["probe_a"]) else _spec["signal_b"]}
	if entity != str(_spec["console"]):
		return {"ok": false, "code": "EXP08_UNKNOWN_TARGET"}
	if action == "reset":
		if _phase != "faulted":
			return {"ok": false, "code": "EXP08_NOT_FAULTED"}
		_phase = "route"
		_route = ""
		_stable_ticks = 0
		_resets += 1
		return {"ok": true, "phase": _phase, "recovered": true}
	if action == "isolate" or action == "reroute":
		if _phase != "route":
			return {"ok": false, "code": "EXP08_PROBES_REQUIRED"}
		if action == "isolate" and bool(facts.get("spur_on", true)):
			return {"ok": false, "code": "EXP08_ISOLATION_NEEDS_SPUR_OFF"}
		if action == "reroute" and not bool(facts.get("spur_on", false)):
			return {"ok": false, "code": "EXP08_REROUTE_NEEDS_SPUR_ON"}
		if action == "reroute" and _spares == 0:
			return {"ok": false, "code": "EXP08_SPARE_RELAY_EXHAUSTED"}
		if not bool(facts.get("west_inspected", false)):
			return {"ok": false, "code": "EXP08_HOST_METER_EVIDENCE_REQUIRED"}
		if action == "reroute":
			_spares -= 1
		_route = action
		_phase = "prepared"
		return {"ok": true, "phase": _phase, "route": _route}
	if action == "stabilize":
		if _phase != "prepared":
			return {"ok": false, "code": "EXP08_ROUTE_NOT_PREPARED"}
		if not _ready_for_stability(facts):
			return {"ok": false, "code": "EXP08_HOST_STABILITY_EVIDENCE_REQUIRED"}
		_stable_ticks = 0
		_phase = "holding"
		return {"ok": true, "phase": _phase}
	if action == "certify":
		if _phase != "verified":
			return {"ok": false, "code": "EXP08_HOLD_NOT_VERIFIED"}
		_phase = "complete"
		return {"ok": true, "phase": _phase, "route": _route}
	return {"ok": false, "code": "EXP08_ACTION_INVALID"}


## One progression tick from SessionHost itself, after the real grid tick.
## Loss of either physical feeder, repair, or the hazard-safe window trips the
## ongoing hold and requires a new host-authorized reset. It never rewrites grid.
func advance(facts: Dictionary) -> void:
	if _phase != "holding":
		return
	if not _ready_for_stability(facts):
		_phase = "faulted"
		_stable_ticks = 0
		_faults += 1
		return
	_stable_ticks += 1
	var required: int = int(_spec["hold_ticks"])
	if _route == "reroute":
		required += int(_spec["alternate_extra_ticks"])
	if _stable_ticks >= required:
		_phase = "verified"


func solved() -> bool:
	return _phase == "complete" and not _spec.is_empty()


func snapshot() -> Dictionary:
	return {
		"ok": not _spec.is_empty(), "level_id": _spec.get("level_id", ""),
		"scenario_key": _spec.get("scenario_key", ""),
		"phase": _phase, "route": _route, "scans": _scans.duplicate(true),
		"stable_ticks": _stable_ticks, "hold_ticks": int(_spec.get("hold_ticks", 0)) + \
			(int(_spec.get("alternate_extra_ticks", 0)) if _route == "reroute" else 0),
		"faults": _faults, "resets": _resets, "spares": _spares,
		"solved": solved(), "qualification": QUALIFICATION
	}
