extends RefCounted
## EXP06 authoritative environmental-hazard and encounter-puzzle layer.
##
## The book is committed source content, never a client or save payload.
## Only accepted SessionHost intents and server-owned ticks may advance puzzles.
## Hazard gates run BEFORE SessionHost effects. This module does not issue
## receipts, edit the grid, rewrite saves or supersede the original C01-C12.
##
## Human/controller/pathfinding qualification remains explicitly held.

const BOOK_PATH: String = "res://scenes/expeditions/bespoke_encounters.json"
const FAMILIES: Array[String] = [
	"fault_trace", "feeder_pulse", "post_repair_audit", "stability_hold",
	"spur_isolation", "load_rebalance", "relay_coincidence", "circuit_pair"
]
const HAZARDS: Array[String] = [
	"water_ingress", "gust_lockout", "static_discharge", "thermal_spike",
	"signal_interference", "mechanical_vibration", "dust_cloud",
	"equipment_condensation"
]
const SITE_TYPES: Array[String] = [
	"distribution", "transport", "health", "commerce", "waterworks",
	"communications", "education", "shelter"
]
const QUALIFICATION: String = "SOURCE_ONLY_NO_PHYSICAL_CONTROLLER_OR_RELEASE_QUALIFICATION"

var _spec: Dictionary = {}
var _tick: int = 0
var _inspection_count: int = 0
var _last_inspection_tick: int = -1
var _spaced_inspections: bool = false
var _inspected_after_east_before_repair: bool = false
var _post_repair_inspected: bool = false
var _east_enable_tick: int = -1
var _relay_synced: bool = false
var _pulse_phase: int = 0
var _spur_phase: int = 0
var _rebalance_phase: int = 0
var _stable_ticks: int = 0
var _west_restored: bool = false
var _east_enabled: bool = false
var _exposure_ticks: int = 0


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return parsed if parsed is Dictionary else {}


static func _numeric_valid(value: Variant, lower: int, upper: int) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number == floorf(number) and number >= lower and number <= upper


static func entry_for(book: Dictionary, level: Dictionary, location: Dictionary) -> Dictionary:
	for raw: Variant in book.get("entries", []):
		if not raw is Dictionary:
			return {}
		var entry: Dictionary = raw
		if entry.get("level_id") != level.get("id"):
			continue
		if entry.get("location_id") != location.get("id") or \
				entry.get("source_puzzle_identity") != level.get("puzzle_identity") or \
				entry.get("site") != location.get("archetype") or \
				entry.get("risk") != location.get("risk") or \
				entry.get("title") != level.get("title") or \
				entry.get("scene") != location.get("environment"):
			return {}
		var motifs: Array = []
		for index: int in range(3):
			motifs.append(level["tasks"][index]["mechanic"])
		if entry.get("source_motifs") != motifs:
			return {}
		return entry.duplicate(true)
	return {}


## Pin every level against the EXP01 source atlas. A malformed or foreign
## record fails closed rather than silently assigning another level's mechanic.
static func inspect(atlas: Dictionary, book: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	if book.get("schema_version") != 1 or \
			book.get("authority") != "EXP06_HOST_PINNED_SOURCE_ONLY" or \
			book.get("atlas_revision") != atlas.get("revision"):
		failures.append("BOOK_SCHEMA_OR_SOURCE_REVISION")
	var entries: Variant = book.get("entries")
	if not entries is Array or (entries as Array).size() != 200:
		return {"ok": false, "code": "INCORRECT_ENCOUNTER_COUNT", "failures": failures}
	var seen: Dictionary = {}
	var unique: Dictionary = {}
	var families: Dictionary = {}
	var hazards: Dictionary = {}
	var locations: Dictionary = {}
	for location: Dictionary in atlas.get("locations", []):
		locations[location.get("id", "")] = location
	for entry_raw: Variant in entries:
		if not entry_raw is Dictionary:
			failures.append("MALFORMED_ENCOUNTER")
			continue
		var entry: Dictionary = entry_raw
		var id: String = str(entry.get("level_id", ""))
		if seen.has(id):
			failures.append("DUPLICATE_LEVEL_" + id)
		seen[id] = true
		var fingerprint: String = str(entry.get("encounter_key", ""))
		if fingerprint.length() < 30 or unique.has(fingerprint):
			failures.append("DUPLICATE_ENCOUNTER_" + id)
		unique[fingerprint] = true
		var puzzle_raw: Variant = entry.get("puzzle")
		var hazard_raw: Variant = entry.get("hazard")
		if not (puzzle_raw is Dictionary and hazard_raw is Dictionary):
			failures.append("MISSING_MECHANIC_" + id)
			continue
		var puzzle: Dictionary = puzzle_raw
		var hazard: Dictionary = hazard_raw
		var family: String = str(puzzle.get("family", ""))
		var hazard_kind: String = str(hazard.get("kind", ""))
		if not FAMILIES.has(family) or not HAZARDS.has(hazard_kind) or \
				not SITE_TYPES.has(str(entry.get("site", ""))):
			failures.append("UNSUPPORTED_MECHANIC_" + id)
		families[family] = true
		hazards[hazard_kind] = true
		if not _numeric_valid(puzzle.get("hold_ticks"), 140, 300) or \
				not _numeric_valid(puzzle.get("min_gap_ticks"), 2, 30) or \
				not _numeric_valid(puzzle.get("sync_ticks"), 90, 400) or \
				not _numeric_valid(hazard.get("period_ticks"), 30, 180) or \
				not _numeric_valid(hazard.get("active_ticks"), 1, 45) or \
				not _numeric_valid(hazard.get("phase_offset"), 0, 180) or \
				not ["switches", "repairs", "both"].has(hazard.get("blocks")) or \
				int(hazard.get("active_ticks", 0)) >= int(hazard.get("period_ticks", 0)):
			failures.append("INVALID_MECHANIC_PARAMETERS_" + id)
		var source_level: Dictionary = {}
		for level: Dictionary in atlas.get("levels", []):
			if level.get("id") == id:
				source_level = level
				break
		if source_level.is_empty() or not locations.has(entry.get("location_id", "")) or \
				entry_for({"entries": [entry]}, source_level, \
				locations.get(entry.get("location_id", ""), {})).is_empty():
			failures.append("SOURCE_IDENTITY_MISMATCH_" + id)
	if families.size() != 8 or hazards.size() != 8 or seen.size() != 200:
		failures.append("MISSING_REQUIRED_DIVERSITY")
	return {"ok": failures.is_empty(), "code": "OK" if failures.is_empty() else "INVALID_ENCOUNTERS",
		"failures": failures, "levels": seen.size(), "families": families.size(),
		"hazards": hazards.size(), "unique_encounters": unique.size()}


func configure(spec: Dictionary) -> Dictionary:
	if not _spec.is_empty():
		return {"ok": false, "code": "ALREADY_CONFIGURED"}
	if not FAMILIES.has(str(spec.get("puzzle", {}).get("family", ""))) or \
			not HAZARDS.has(str(spec.get("hazard", {}).get("kind", ""))):
		return {"ok": false, "code": "INVALID_ENCOUNTER"}
	_spec = spec.duplicate(true)
	return {"ok": true, "level_id": str(_spec["level_id"])}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


func _hazard_phase() -> int:
	var hazard: Dictionary = _spec.get("hazard", {})
	var period: int = maxi(1, int(hazard.get("period_ticks", 1)))
	return (_tick + int(hazard.get("phase_offset", 0))) % period


func hazard_active() -> bool:
	return not _spec.is_empty() and \
		_hazard_phase() < int((_spec["hazard"] as Dictionary)["active_ticks"])


func _safe_in_ticks() -> int:
	if not hazard_active():
		return 0
	return int((_spec["hazard"] as Dictionary)["active_ticks"]) - _hazard_phase()


## Preflight only with a host-selected peer and a source-matching session
## envelope. All normal envelope/peer/sequence/range/tool validation still
## happens independently in SessionHost.receive().
func preflight(kind: String, entity: String) -> Dictionary:
	if _spec.is_empty():
		return {"ok": false, "code": "EXP06_NOT_CONFIGURED"}
	if kind == "request_extract" and entity == "ZONE_EXTRACT" and not solved():
		return {"ok": false, "code": "EXP06_PUZZLE_UNRESOLVED",
			"family": (_spec["puzzle"] as Dictionary)["family"]}
	var blocking: String = str((_spec["hazard"] as Dictionary)["blocks"])
	var at_switch: bool = kind == "toggle_switch" and \
		["SW_EAST", "SW_GRID_SPUR", "SW_WEST_SPUR", "SW_SIGN"].has(entity)
	var at_repair: bool = kind == "repair_step" and entity == "R_WEST"
	if hazard_active() and ((at_switch and blocking != "repairs") or \
			(at_repair and blocking != "switches")):
		return {"ok": false, "code": "EXP06_UNSAFE_HAZARD_WINDOW",
			"hazard": (_spec["hazard"] as Dictionary)["kind"],
			"safe_in_ticks": _safe_in_ticks()}
	return {"ok": true}


func _synchronize(grid_state: Dictionary, repairs: Dictionary) -> void:
	var edges: Dictionary = grid_state.get("edges", {})
	var east: Dictionary = edges.get("E_GRID_EAST", {})
	_east_enabled = bool(east.get("enabled", false))
	var west: Dictionary = grid_state.get("nodes", {}).get("WEST", {})
	_west_restored = str(repairs.get("R_WEST", {}).get("state", "")) == "restored" and \
		not bool(west.get("failed", true)) and not bool(west.get("tripped", true))


## No client-reported success/progress is accepted: caller has already
## received a nonduplicate, positive SessionHost response and supplies live
## canonical grid/repair snapshots from that same host.
func accepted(kind: String, entity: String, _payload: Dictionary,
		grid_state: Dictionary, repairs: Dictionary) -> void:
	if _spec.is_empty():
		return
	_synchronize(grid_state, repairs)
	if kind == "inspect" and entity == "PANEL_WEST":
		if _last_inspection_tick >= 0 and \
				_tick - _last_inspection_tick >= int((_spec["puzzle"] as Dictionary)["min_gap_ticks"]):
			_spaced_inspections = true
		_last_inspection_tick = _tick
		_inspection_count += 1
		if _west_restored:
			_post_repair_inspected = true
		elif _east_enabled:
			_inspected_after_east_before_repair = true
		if _east_enabled and _east_enable_tick >= 0 and \
				_tick - _east_enable_tick <= int((_spec["puzzle"] as Dictionary)["sync_ticks"]):
			_relay_synced = true
	if kind == "toggle_switch" and entity == "SW_EAST":
		if _east_enabled:
			_east_enable_tick = _tick
			if _pulse_phase == 0:
				_pulse_phase = 1
			elif _pulse_phase == 2:
				_pulse_phase = 3
			if _rebalance_phase == 1 and _west_restored:
				_rebalance_phase = 2
		else:
			if _pulse_phase == 1:
				_pulse_phase = 2
			if _west_restored:
				_rebalance_phase = 1
	if kind == "toggle_switch" and entity == "SW_GRID_SPUR":
		var spur: Dictionary = grid_state.get("edges", {}).get("E_GRID_SPUR", {})
		if bool(spur.get("enabled", false)):
			if _spur_phase == 0:
				_spur_phase = 1
		elif _spur_phase == 1:
			_spur_phase = 2


## Advance ONLY from the server simulation's fixed tick and true world
## position. Exposure is diagnostic, not invented health damage or a reward.
func advance(host_position: Vector3, repair_position: Vector3,
		grid_state: Dictionary, repairs: Dictionary) -> void:
	if _spec.is_empty():
		return
	_tick += 1
	_synchronize(grid_state, repairs)
	if hazard_active() and host_position.is_finite() and \
			host_position.distance_to(repair_position) < 2.5:
		_exposure_ticks += 1
	if _west_restored and _east_enabled:
		_stable_ticks += 1
	else:
		_stable_ticks = 0


func solved() -> bool:
	if _spec.is_empty() or not _west_restored or not _east_enabled or \
			_inspection_count < 1:
		return false
	var puzzle: Dictionary = _spec["puzzle"]
	match str(puzzle["family"]):
		"fault_trace":
			return _spaced_inspections
		"feeder_pulse":
			return _pulse_phase == 3
		"post_repair_audit":
			return _post_repair_inspected
		"stability_hold":
			return _stable_ticks >= int(puzzle["hold_ticks"])
		"spur_isolation":
			return _spur_phase == 2
		"load_rebalance":
			return _rebalance_phase == 2
		"relay_coincidence":
			return _relay_synced
		"circuit_pair":
			return _inspected_after_east_before_repair and _post_repair_inspected
	return false


func instruction() -> String:
	if _spec.is_empty():
		return ""
	var puzzle: Dictionary = _spec["puzzle"]
	match str(puzzle["family"]):
		"fault_trace":
			return "Repeat WEST meter inspection after at least %d host ticks." % int(puzzle["min_gap_ticks"])
		"feeder_pulse":
			return "Inspect WEST; cycle EAST feed ON / OFF / ON, then restore WEST."
		"post_repair_audit":
			return "After WEST repair is restored, reinspect the WEST meter."
		"stability_hold":
			return "Keep the restored WEST repair and EAST feed stable for %d consecutive ticks." % int(puzzle["hold_ticks"])
		"spur_isolation":
			return "After WEST inspection, pulse GRID SPUR ON then OFF; leave EAST supplied."
		"load_rebalance":
			return "After WEST repair, switch EAST feed OFF then ON to prove recovery."
		"relay_coincidence":
			return "After switching EAST ON, inspect WEST within %d host ticks." % int(puzzle["sync_ticks"])
		"circuit_pair":
			return "Inspect WEST with EAST online before repair, then reinspect after repair."
	return ""


func snapshot() -> Dictionary:
	if _spec.is_empty():
		return {"ok": false, "code": "EXP06_NOT_CONFIGURED"}
	var hazard: Dictionary = _spec["hazard"]
	return {
		"ok": true, "level_id": _spec["level_id"], "tick": _tick,
		"family": (_spec["puzzle"] as Dictionary)["family"],
		"puzzle_solved": solved(), "instruction": instruction(),
		"west_inspections": _inspection_count, "stable_ticks": _stable_ticks,
		"hazard_kind": hazard["kind"], "hazard_risk": _spec["risk"],
		"hazard_blocks": hazard["blocks"], "hazard_active": hazard_active(),
		"safe_in_ticks": _safe_in_ticks(), "exposure_ticks": _exposure_ticks,
		"qualification": QUALIFICATION
	}
