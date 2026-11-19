extends RefCounted
## EXP011 — source-pinned, host-authoritative temporary critical-service balancing.
## Capacity, deadlines, stabilization and safety are decided by fixed host ticks,
## never by a peer's clock, inventory or claimed completion. Source/headless only.

const BOOK_PATH: String = "res://scenes/expeditions/critical_service_loads.json"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const MODES: Array[String] = ["cascade", "triage", "interlock"]
const MAX_HISTORY: int = 24

var _spec: Dictionary = {}
var _circuits: Dictionary = {}
var _active: Dictionary = {}
var _opened: bool = false
var _certified: bool = false
var _clock: int = 0
var _late: int = 0
var _aborts: int = 0
var _reopens: int = 0
var _history: Array[Dictionary] = []


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return decoded if decoded is Dictionary else {}


static func entry_for(book: Dictionary, level: Dictionary, logistics: Dictionary) -> Dictionary:
	for raw: Variant in book.get("entries", []):
		if not raw is Dictionary:
			return {}
		var entry: Dictionary = raw
		if entry.get("level_id") != level.get("id"):
			continue
		if entry.get("location_id") != level.get("location_id") or \
				entry.get("source_puzzle_identity") != level.get("puzzle_identity") or \
				entry.get("logistics_key") != logistics.get("logistics_key") or \
				entry.get("site") != logistics.get("site"):
			return {}
		return entry.duplicate(true)
	return {}


## Whole-book inspection blocks catalog substitution and authored target inflation.
static func inspect(atlas: Dictionary, logistics_book: Dictionary, book: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if book.get("schema_version") != 1 or book.get("authority") != "EXP011_HOST_LOAD_BALANCING" or \
			book.get("atlas_revision") != atlas.get("revision") or \
			book.get("qualification") != QUALIFICATION:
		errors.append("HEADER_INVALID")
	var entries: Variant = book.get("entries")
	if not entries is Array or (entries as Array).size() != 200:
		return {"ok": false, "code": "EXP011_COUNT_INVALID", "failures": errors}
	var levels: Dictionary = {}
	var manifests: Dictionary = {}
	for level: Dictionary in atlas.get("levels", []):
		levels[str(level["id"])] = level
	for manifest: Dictionary in logistics_book.get("entries", []):
		manifests[str(manifest["level_id"])] = manifest
	var seen: Dictionary = {}
	var targets: Dictionary = {}
	var keys: Dictionary = {}
	var modes: Dictionary = {}
	for i: int in range(200):
		if not entries[i] is Dictionary:
			errors.append("ENTRY_NOT_OBJECT")
			continue
		var entry: Dictionary = entries[i]
		var lid: String = str(entry.get("level_id", ""))
		if seen.has(lid) or not levels.has(lid) or not manifests.has(lid):
			errors.append("LEVEL_INVALID_" + lid)
			continue
		seen[lid] = true
		var manifest: Dictionary = manifests[lid]
		if entry_for({"entries": [entry]}, levels[lid], manifest).is_empty():
			errors.append("SOURCE_DRIFT_" + lid)
		var mode: String = MODES[i % 3]
		modes[mode] = true
		var suffix: String = lid.trim_prefix("LV_")
		var key: String = str(manifest["logistics_key"]) + "|EXP011|" + mode
		if entry.get("load_key") != key or keys.has(key) or entry.get("mode") != mode:
			errors.append("KEY_OR_MODE_INVALID_" + lid)
		keys[key] = true
		if entry.get("board") != "LB_%s_BOARD" % suffix or \
				entry.get("console") != "LB_%s_CTRL" % suffix or \
				entry.get("board_anchor") != "PANEL_WEST" or \
				entry.get("console_anchor") != "R_WEST" or \
				float(entry.get("capacity_pu", -1)) != 6.0:
			errors.append("BOARD_INVALID_" + lid)
		var services: Variant = entry.get("services")
		if not services is Array or (services as Array).size() != 3:
			errors.append("SERVICES_INVALID_" + lid)
			continue
		var demand: Array = [[4, 3, 2], [3, 2, 1], [2, 2, 2]][i % 3]
		var ids: Array[String] = ["LB_%s_A" % suffix, "LB_%s_B" % suffix, "LB_%s_C" % suffix]
		var anchors: Array[String] = ["PANEL_SPUR", "R_WEST", "PANEL_WEST"]
		var names: Array[String] = [str(manifest["jobs"][0]["cargo"]), str(manifest["jobs"][1]["cargo"]),
			str(manifest["site"]) + " continuity feeder"]
		for j: int in range(3):
			if not services[j] is Dictionary:
				errors.append("SERVICE_NOT_OBJECT_" + lid)
				continue
			var service: Dictionary = services[j]
			var requires: Array = []
			if mode == "cascade" and j > 0:
				requires = [ids[j - 1]]
			if mode == "interlock" and j == 2:
				requires = [ids[0], ids[1]]
			if service.get("id") != ids[j] or service.get("anchor") != anchors[j] or \
					service.get("name") != names[j] or \
					float(service.get("demand_pu", -1)) != float(demand[j]) or \
					float(service.get("dwell_ticks", -1)) != float(5 + i % 4 + j * 2) or \
					float(service.get("deadline_ticks", -1)) != float(11 + i % 7 + j * 6) or \
					service.get("requires") != requires or \
					service.get("priority") != ["critical", "priority", "support"][j]:
				errors.append("SERVICE_DRIFT_" + lid)
		for id: String in [str(entry["board"]), str(entry["console"]), ids[0], ids[1], ids[2]]:
			if targets.has(id):
				errors.append("DUPLICATE_TARGET_" + id)
			targets[id] = true
	if seen.size() != 200 or keys.size() != 200 or targets.size() != 1000 or modes.size() != 3:
		errors.append("COVERAGE_INVALID")
	return {"ok": errors.is_empty(), "code": "OK" if errors.is_empty() else "EXP011_INVALID",
		"levels": seen.size(), "circuits": seen.size() * 3,
		"targets": targets.size(), "modes": modes.size(), "failures": errors}


func configure(entry: Dictionary) -> Dictionary:
	if not _spec.is_empty() or not entry.has("load_key") or \
			not entry.get("services") is Array or (entry["services"] as Array).size() != 3:
		return {"ok": false, "code": "EXP011_CONFIG_INVALID"}
	_spec = entry.duplicate(true)
	for service: Dictionary in _spec["services"]:
		_circuits[str(service["id"])] = {"status": "pending", "ticks": 0, "late": false}
	return {"ok": true}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


func target_ids() -> Array[String]:
	var ids: Array[String] = []
	if _spec.is_empty():
		return ids
	ids.append(str(_spec["board"]))
	ids.append(str(_spec["console"]))
	for service: Dictionary in _spec["services"]:
		ids.append(str(service["id"]))
	return ids


func _service(id: String) -> Dictionary:
	for service: Dictionary in _spec.get("services", []):
		if service.get("id") == id:
			return service
	return {}


func _safe(facts: Dictionary) -> bool:
	return bool(facts.get("logistics_solved", false)) and \
			bool(facts.get("consequences_solved", false)) and \
			bool(facts.get("faults_solved", false)) and \
			bool(facts.get("west_restored", false)) and \
			bool(facts.get("east_on", false)) and \
			not bool(facts.get("hazard_active", true))


func _log(event: String, id: String) -> void:
	_history.append({"tick": _clock, "event": event, "target": id})
	while _history.size() > MAX_HISTORY:
		_history.pop_front()


func _used_pu() -> int:
	var used: int = 0
	for id: String in _active:
		used += int(_service(id)["demand_pu"])
	return used


func _all_latched() -> bool:
	if _circuits.size() != 3:
		return false
	for state: Dictionary in _circuits.values():
		if state["status"] != "latched":
			return false
	return true


## Only one action string may arrive, after SessionHost dedupe, range and LoS.
func operate(id: String, action: String, facts: Dictionary) -> Dictionary:
	if _spec.is_empty():
		return {"ok": false, "code": "EXP011_NOT_CONFIGURED"}
	if not target_ids().has(id):
		return {"ok": false, "code": "EXP011_UNKNOWN_TARGET"}
	if id == str(_spec["board"]):
		if action != "open" or _opened or not _safe(facts):
			return {"ok": false, "code": "EXP011_BOARD_INTERLOCK"}
		_opened = true
		_log("BOARD_OPENED", id)
		return {"ok": true, "capacity_pu": int(_spec["capacity_pu"]), "mode": _spec["mode"]}
	if id == str(_spec["console"]):
		if action != "certify" or _certified or not _opened or \
				not _safe(facts) or not _active.is_empty() or not _all_latched():
			return {"ok": false, "code": "EXP011_CERTIFICATION_INTERLOCK"}
		_certified = true
		_log("SERVICE_BALANCE_CERTIFIED", id)
		return {"ok": true, "certified": true, "late": _late}
	if not _opened or not _safe(facts):
		return {"ok": false, "code": "EXP011_HOST_UNSAFE"}
	var service: Dictionary = _service(id)
	var status: String = str(_circuits[id]["status"])
	if action == "recheck" and status == "recheck":
		_circuits[id]["status"] = "latched"
		_log("SERVICE_RECHECKED", id)
		return {"ok": true, "rechecked": id}
	if action == "shed" and _active.has(id):
		_active.erase(id)
		if status == "stable":
			_circuits[id]["status"] = "latched"
			var late: bool = _clock > int(service["deadline_ticks"])
			_circuits[id]["late"] = late
			if late:
				_late += 1
			_log("SERVICE_LATCHED", id)
			return {"ok": true, "latched": id, "late": late}
		_circuits[id]["status"] = "pending"
		_circuits[id]["ticks"] = 0
		_aborts += 1
		_log("EARLY_SHED", id)
		return {"ok": true, "aborted": id}
	if action != "energize" or status != "pending":
		return {"ok": false, "code": "EXP011_CIRCUIT_ACTION_INVALID"}
	for dependency: Variant in service["requires"]:
		if not _circuits.has(str(dependency)) or _circuits[str(dependency)]["status"] != "latched":
			return {"ok": false, "code": "EXP011_DEPENDENCY_UNMET"}
	if int(service["demand_pu"]) + _used_pu() > int(_spec["capacity_pu"]):
		return {"ok": false, "code": "EXP011_CAPACITY_EXCEEDED"}
	if _spec["mode"] == "interlock" and \
			((id.ends_with("_A") and _active.has(id.trim_suffix("_A") + "_B")) or \
			(id.ends_with("_B") and _active.has(id.trim_suffix("_B") + "_A"))):
		return {"ok": false, "code": "EXP011_CROSS_FEED_INTERLOCK"}
	_active[id] = true
	_circuits[id]["status"] = "warming"
	_circuits[id]["ticks"] = 0
	_log("SERVICE_ENERGIZED", id)
	return {"ok": true, "energized": id, "used_pu": _used_pu()}


## Fixed 10 Hz host clock. Loss of upstream safety never mints reserve power.
## Stabilized circuits can be rechecked after loss; interrupted work must restart.
func advance(facts: Dictionary) -> void:
	if _spec.is_empty() or not _opened:
		return
	if not _safe(facts):
		if _certified:
			_certified = false
			_reopens += 1
		var changed: bool = false
		for id: String in _circuits:
			var status: String = str(_circuits[id]["status"])
			if status == "latched":
				_circuits[id]["status"] = "recheck"
				changed = true
			elif status == "warming" or status == "stable":
				_circuits[id]["status"] = "pending"
				_circuits[id]["ticks"] = 0
				changed = true
		_active.clear()
		if changed:
			_log("UNSAFE_SUPPLY_REOPENED", str(_spec["console"]))
		return
	if _certified:
		return
	_clock += 1
	for id: String in _active:
		if _circuits[id]["status"] != "warming":
			continue
		_circuits[id]["ticks"] = int(_circuits[id]["ticks"]) + 1
		if int(_circuits[id]["ticks"]) >= int(_service(id)["dwell_ticks"]):
			_circuits[id]["status"] = "stable"
			_log("SERVICE_STABILIZED", id)


func solved() -> bool:
	return _certified and _all_latched() and _active.is_empty()


func snapshot() -> Dictionary:
	return {"ok": not _spec.is_empty(), "level_id": _spec.get("level_id", ""),
		"load_key": _spec.get("load_key", ""), "mode": _spec.get("mode", ""),
		"opened": _opened, "certified": _certified, "solved": solved(),
		"capacity_pu": int(_spec.get("capacity_pu", 0)), "used_pu": _used_pu(),
		"tick": _clock, "late": _late, "aborts": _aborts, "reopens": _reopens,
		"circuits": _circuits.duplicate(true), "history": _history.duplicate(true),
		"qualification": QUALIFICATION}
