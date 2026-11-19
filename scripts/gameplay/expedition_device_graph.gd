extends RefCounted
## EXP07: source-pinned, host-operated device graph for experimental expeditions.
## This has no authority outside an explicitly opted-in ExpeditionHostSession.
## Client payloads contain only the requested operation. Preconditions use
## server-owned completion and grid/repair evidence; early operations can jam
## a device and require a separate recovery procedure.
const BOOK_PATH: String = "res://scenes/expeditions/bespoke_device_graphs.json"
const QUALIFICATION: String = "SOURCE_ONLY_NO_HUMAN_CONTROLLER_OR_RELEASE_CERTIFICATION"
const ACTIONS: Dictionary = {
	"distribution": ["trace", "lockout", "phase_match", "bus_tie", "signoff", "stabilize"],
	"transport": ["survey", "brake", "align", "energize", "certify", "reroute"],
	"health": ["sample", "isolate", "flush", "transfer", "validate", "purge"],
	"commerce": ["trace", "seal", "balance", "supply", "audit", "bypass"],
	"waterworks": ["read", "shutoff", "bleed", "prime", "verify", "backwash"],
	"communications": ["scan", "shield", "synchronize", "route", "confirm", "retune"],
	"education": ["inspect", "partition", "calibrate", "restore", "check", "test"],
	"shelter": ["assess", "secure", "equalize", "handoff", "release", "reserve"]
}
const ANCHORS: Array[String] = ["PANEL_WEST", "PANEL_SPUR", "R_WEST",
	"SW_EAST", "SW_GRID_SPUR", "SW_WEST_SPUR"]
const EVIDENCE: Array[String] = ["none", "west_inspected", "east_on", "west_restored"]
var _graph: Dictionary = {}
var _nodes: Dictionary = {}
var _status: Dictionary = {}
var _faults: int = 0
var _resets: int = 0


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return parsed if parsed is Dictionary else {}


static func entry_for(book: Dictionary, level: Dictionary, encounter: Dictionary) -> Dictionary:
	for raw: Variant in book.get("entries", []):
		if not raw is Dictionary:
			return {}
		var entry: Dictionary = raw
		if entry.get("level_id") != level.get("id"):
			continue
		if entry.get("location_id") != level.get("location_id") or \
				entry.get("source_puzzle_identity") != level.get("puzzle_identity") or \
				entry.get("encounter_key") != encounter.get("encounter_key") or \
				entry.get("site") != encounter.get("site") or \
				entry.get("source_climate") != encounter.get("source_climate"):
			return {}
		return entry.duplicate(true)
	return {}


## Independently validate all 200 graphs and their EXP01/EXP06 source pins.
## Dependencies must point backward, excluding cyclic or dangling device plans.
static func inspect(atlas: Dictionary, encounters: Dictionary, book: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if book.get("schema_version") != 1 or \
			book.get("authority") != "EXP07_HOST_DEVICE_GRAPH" or \
			book.get("atlas_revision") != atlas.get("revision"):
		errors.append("BAD_BOOK_REVISION")
	var entries: Variant = book.get("entries")
	if not entries is Array or (entries as Array).size() != 200:
		return {"ok": false, "code": "INCORRECT_GRAPH_COUNT", "failures": errors}
	var levels: Dictionary = {}
	for level: Dictionary in atlas.get("levels", []):
		levels[str(level.get("id", ""))] = level
	var encounters_by_level: Dictionary = {}
	for record: Dictionary in encounters.get("entries", []):
		encounters_by_level[str(record.get("level_id", ""))] = record
	var seen: Dictionary = {}
	var signatures: Dictionary = {}
	var kinds: Dictionary = {}
	for raw: Variant in entries:
		if not raw is Dictionary:
			errors.append("MALFORMED_GRAPH")
			continue
		var entry: Dictionary = raw
		var level_id: String = str(entry.get("level_id", ""))
		if seen.has(level_id) or not levels.has(level_id) or not encounters_by_level.has(level_id):
			errors.append("DUPLICATE_OR_FOREIGN_LEVEL_" + level_id)
			continue
		seen[level_id] = true
		if entry_for({"entries": [entry]}, levels[level_id], encounters_by_level[level_id]).is_empty():
			errors.append("SOURCE_IDENTITY_MISMATCH_" + level_id)
		var site: String = str(entry.get("site", ""))
		if not ACTIONS.has(site):
			errors.append("UNKNOWN_SITE_" + level_id)
			continue
		var nodes: Variant = entry.get("nodes")
		if not nodes is Array or (nodes as Array).size() < 5 or (nodes as Array).size() > 6:
			errors.append("INVALID_NODES_" + level_id)
			continue
		var previous: Dictionary = {}
		var signature: Array[String] = []
		var fault_nodes: int = 0
		var recovery_nodes: Dictionary = {}
		for index: int in range((nodes as Array).size()):
			var node_raw: Variant = nodes[index]
			if not node_raw is Dictionary:
				errors.append("NON_OBJECT_NODE_" + level_id)
				continue
			var node: Dictionary = node_raw
			var id: String = str(node.get("id", ""))
			var action: String = str(node.get("action", ""))
			var evidence: String = str(node.get("requires", ""))
			var anchor: String = str(node.get("anchor", ""))
			var dependencies: Variant = node.get("depends_on")
			if id != "%s_%s" % [level_id.replace("LV_", "DV_"), char(65 + index)] or \
					previous.has(id) or not (ACTIONS[site] as Array).has(action) or \
					not ANCHORS.has(anchor) or not EVIDENCE.has(evidence) or \
					not dependencies is Array:
				errors.append("INVALID_DEVICE_" + level_id + "_" + str(index))
				continue
			for dependency: Variant in dependencies:
				if not (dependency is String and previous.has(dependency)):
					errors.append("CYCLE_OR_UNKNOWN_DEPENDENCY_" + id)
			if bool(node.get("jam_on_early", false)):
				fault_nodes += 1
				if index < 2 or (dependencies as Array).is_empty():
					errors.append("INVALID_FAULT_PATH_" + id)
				var recovery: String = str(node.get("recovery_after", ""))
				if not previous.has(recovery):
					errors.append("INVALID_RECOVERY_" + id)
				recovery_nodes[recovery] = true
			previous[id] = true
			kinds[action] = true
			signature.append("%s:%s:%s:%s:%s" % [action, anchor, evidence,
				",".join(dependencies), str(node.get("jam_on_early", false))])
		if fault_nodes != 1 or not recovery_nodes.has(str((nodes as Array)[1].get("id", ""))):
			errors.append("RECOVERY_PATH_REQUIRED_" + level_id)
		if str((nodes as Array).back().get("requires", "")) != "west_restored":
			errors.append("FINAL_HOST_EVIDENCE_REQUIRED_" + level_id)
		var fingerprint: String = str(entry.get("graph_key", ""))
		if fingerprint.length() < 24 or signatures.has(fingerprint):
			errors.append("NON_UNIQUE_GRAPH_KEY_" + level_id)
		signatures[fingerprint] = true
		if str(entry.get("graph_key", "")) != "%s|%s|%s" % [
				level_id, str(entry.get("encounter_key", "")),
				str(entry.get("graph_variant", ""))]:
			errors.append("GRAPH_KEY_NOT_PINNED_" + level_id)
	if seen.size() != 200 or kinds.size() < 20:
		errors.append("MISSING_GRAPH_COVERAGE")
	return {"ok": errors.is_empty(), "code": "OK" if errors.is_empty() else "INVALID_GRAPHS",
		"levels": seen.size(), "operations": kinds.size(), "failures": errors}


func configure(entry: Dictionary) -> Dictionary:
	if not _graph.is_empty() or not entry.has("nodes"):
		return {"ok": false, "code": "GRAPH_ALREADY_CONFIGURED_OR_EMPTY"}
	_graph = entry.duplicate(true)
	for node: Dictionary in _graph["nodes"]:
		_nodes[str(node["id"])] = node.duplicate(true)
		_status[str(node["id"])] = "idle"
	return {"ok": true, "devices": _nodes.size()}


func definition_snapshot() -> Dictionary:
	return _graph.duplicate(true)


func device_ids() -> Array[String]:
	var ids: Array[String] = []
	for node: Dictionary in _graph.get("nodes", []):
		ids.append(str(node["id"]))
	return ids


func device_definition(device_id: String) -> Dictionary:
	return (_nodes.get(device_id, {}) as Dictionary).duplicate(true)


func status_for(device_id: String) -> String:
	return str(_status.get(device_id, ""))


func operate(device_id: String, action: String, evidence: Dictionary) -> Dictionary:
	if not _nodes.has(device_id):
		return {"ok": false, "code": "UNKNOWN_EXP07_DEVICE"}
	var node: Dictionary = _nodes[device_id]
	var state: String = str(_status[device_id])
	if action == "reset":
		if state != "jammed" or not bool(node.get("jam_on_early", false)):
			return {"ok": false, "code": "NOT_JAMMED"}
		if _status.get(str(node.get("recovery_after", ""))) != "done":
			return {"ok": false, "code": "RECOVERY_PREPARATION_REQUIRED"}
		_status[device_id] = "idle"
		_resets += 1
		return {"ok": true, "device_state": "idle", "recovered": true}
	if action != str(node["action"]):
		return {"ok": false, "code": "INVALID_DEVICE_ACTION"}
	if state == "done":
		return {"ok": false, "code": "ALREADY_OPERATED"}
	if state == "jammed":
		return {"ok": false, "code": "DEVICE_JAMMED_RESET_REQUIRED"}
	for dependency: String in node["depends_on"]:
		if _status.get(dependency) != "done":
			if bool(node.get("jam_on_early", false)):
				_status[device_id] = "jammed"
				_faults += 1
				return {"ok": true, "device_state": "jammed",
					"code": "HOST_AUTHORIZED_PREMATURE_FAULT"}
			return {"ok": false, "code": "DEVICE_PREREQUISITE_REQUIRED",
				"prerequisite": dependency}
	var requirement: String = str(node.get("requires", "none"))
	if requirement != "none" and not bool(evidence.get(requirement, false)):
		return {"ok": false, "code": "HOST_EVIDENCE_REQUIRED",
			"evidence": requirement}
	_status[device_id] = "done"
	return {"ok": true, "device_state": "done", "action": action}


func solved() -> bool:
	if _status.is_empty():
		return false
	for device_id: String in _status:
		if _status[device_id] != "done":
			return false
	return true


func snapshot() -> Dictionary:
	return {"ok": not _graph.is_empty(), "level_id": _graph.get("level_id", ""),
		"graph_key": _graph.get("graph_key", ""),
		"solved": solved(), "status": _status.duplicate(true),
		"faults": _faults, "resets": _resets, "qualification": QUALIFICATION}
