extends RefCounted
## EXP016 A02: extra source-bound cases on already-authenticated SC stations.
## This machine never accepts job completion, a source graph or a kit balance
## from a client. The original 1000 jobs/economy/save schema remain unchanged.

const BOOK_PATH: String = "res://scenes/expeditions/exp016_casework_a02.json"
const AUTHORITY: String = "EXP016_A02_AUTHENTICATED_CASEWORK"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const GUARDS: Array[String] = [
	"faults_solved", "balancing_solved", "logistics_solved", "consequences_solved"
]
const ACTIONS: Array[String] = [
	"trace", "isolate", "crosscheck", "tag", "compare", "meter",
	"repair", "reconcile", "attest", "stabilize"
]

var _spec: Dictionary = {}
var _phase: String = "locked"
var _route: String = ""
var _kits: int = 0
var _liabilities: int = 0
var _faults: int = 0
var _recoveries: int = 0
var _completed: Dictionary = {}
var _history: Array[Dictionary] = []


static func _reject(code: String) -> Dictionary:
	return {"ok": false, "code": "EXP016_A02_" + code}


static func load_book() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	if not raw is Dictionary or raw.get("schema_version") != 1 or \
			raw.get("authority") != AUTHORITY or \
			raw.get("qualification") != QUALIFICATION or \
			not raw.get("entries") is Array or raw["entries"].size() != 50:
		return {}
	return raw


static func entry_for(book: Dictionary, level_id: String) -> Dictionary:
	var serial: int = int(level_id.trim_prefix("LV_")) if level_id.begins_with("LV_") else -1
	if serial < 1 or serial > 50 or level_id != "LV_%03d" % serial:
		return {}
	var all_entries: Variant = book.get("entries", [])
	if not all_entries is Array or all_entries.size() != 50:
		return {}
	var result: Variant = all_entries[serial - 1]
	if not result is Dictionary or result.get("level_id") != level_id:
		return {}
	return result.duplicate(true)


static func inspect(atlas: Dictionary, investigation_book: Dictionary, book: Dictionary) -> Dictionary:
	if book.get("authority") != AUTHORITY or book.get("qualification") != QUALIFICATION or \
			not book.get("entries") is Array or book["entries"].size() != 50:
		return _reject("BOOK_HEADER")
	var signatures: Dictionary = {}
	for serial: int in range(1, 51):
		var source: Dictionary = atlas["levels"][serial - 1]
		var old: Dictionary = investigation_book["entries"][serial - 1]
		var item: Dictionary = book["entries"][serial - 1]
		if item.get("level_id") != source["id"] or \
				item.get("location_id") != source["location_id"] or \
				item.get("region_id") != source["region_id"] or \
				item.get("source_puzzle_identity") != source["puzzle_identity"] or \
				item.get("source_task_ids") != source["tasks"].map(func(t: Dictionary) -> String: return str(t["id"])) or \
				item.get("source_investigation_serial") != old["case_serial"] or \
				item.get("source_risk") != old["source_risk"] or \
				item.get("targets") != old["targets"] or \
				item.get("recovery_target") != old["recovery_target"]:
			return _reject("SOURCE_DRIFT")
		for mode: String in ["forensic", "field"]:
			var route: Dictionary = item["routes"][mode]
			var steps: Array = route.get("steps", [])
			if steps.size() < 5 or int(route.get("initial_kits", -1)) < 2:
				return _reject("ROUTE_SHAPE")
			var known: Dictionary = {}
			var total_cost: int = 0
			for step: Dictionary in steps:
				var id: String = str(step.get("id", ""))
				if known.has(id) or not ACTIONS.has(str(step.get("kind", ""))) or \
						not ["A", "B", "C"].has(str(step.get("station", ""))) or \
						not GUARDS.has(str(step.get("guard", ""))):
					return _reject("INVALID_STEP")
				for required: String in step.get("requires", []):
					if not known.has(required):
						return _reject("NON_DAG")
				known[id] = true
				total_cost += int(step.get("cost", -1))
			if total_cost > int(route["initial_kits"]) or total_cost < 0:
				return _reject("UNSOLVABLE_KITS")
		# Source-free: station/guards/actions/edges/actual costs, never titles, IDs or clocks.
		var canonical: Array = []
		for route_key: String in ["forensic", "field"]:
			for node: Dictionary in item["routes"][route_key]["steps"]:
				canonical.append([node["kind"], node["station"], node["requires"], node["guard"], node["cost"]])
		var fingerprint: String = JSON.stringify(canonical)
		if signatures.has(fingerprint):
			return _reject("MECHANICAL_CLONE")
		signatures[fingerprint] = true
	return {"ok": true, "case_count": 50, "distinct_mechanics": signatures.size(),
		"qualification": QUALIFICATION}


func configure(entry: Dictionary) -> Dictionary:
	if entry.is_empty() or not entry.has("routes"):
		return _reject("UNPINNED_CASE")
	_spec = entry.duplicate(true)
	return {"ok": true}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


func target_ids() -> Array:
	return _spec.get("targets", {}).values()


func started() -> bool:
	return _phase != "locked"


func needs_action() -> bool:
	return _phase != "solved"


func solved() -> bool:
	return _phase == "solved"


func begin() -> Dictionary:
	if _spec.is_empty() or _phase != "locked":
		return _reject("BEGIN_UNAVAILABLE")
	_phase = "choose"
	return {"ok": true, "code": "CASE_OPEN"}


func _record(event: String) -> void:
	_history.append({"event": event, "route": _route, "steps": _completed.size(),
		"kits": _kits, "liabilities": _liabilities})
	if _history.size() > 32:
		_history.pop_front()


func operate(entity: String, action: String, facts: Dictionary) -> Dictionary:
	if _phase == "locked" or _phase == "solved":
		return _reject("ACTION_UNAVAILABLE")
	var targets: Dictionary = _spec["targets"]
	if not targets.values().has(entity):
		return _reject("FOREIGN_TARGET")
	if _phase == "choose":
		var chosen: String = action.trim_prefix("case_")
		if not ["forensic", "field"].has(chosen) or \
				entity != str(targets["A" if chosen == "forensic" else "B"]):
			return _reject("INVALID_ROUTE")
		_route = chosen
		var route: Dictionary = _spec["routes"][_route]
		_kits = int(route["initial_kits"])
		_liabilities = int(route["liability_on_select"])
		_phase = "working"
		_record("choose_" + chosen)
		return {"ok": true, "code": "CASE_ROUTE_SELECTED", "route": chosen}
	if _phase == "fault":
		if entity != str(_spec["recovery_target"]) or action != "case_recover":
			return _reject("RECOVERY_TARGET_REQUIRED")
		if _kits < 1:
			return _reject("RECOVERY_KIT_EXHAUSTED")
		_kits -= 1
		_recoveries += 1
		_phase = "working"
		_record("recovered")
		return {"ok": true, "code": "CASE_RECOVERED"}
	if _phase != "working":
		return _reject("BAD_PHASE")
	var steps: Array = _spec["routes"][_route]["steps"]
	var frontier: Array = []
	for step: Dictionary in steps:
		if _completed.has(str(step["id"])):
			continue
		var available: bool = true
		for requirement: String in step["requires"]:
			if not _completed.has(requirement):
				available = false
		if available:
			frontier.append(step)
	for step: Dictionary in frontier:
		if entity != str(targets[str(step["station"])]) or \
				action != "case_" + str(step["kind"]):
			continue
		if not bool(facts.get(str(step["guard"]), false)):
			_phase = "fault"
			_faults += 1
			_liabilities += 1
			_record("unsafe_guard")
			return _reject("GUARD_FAULT_RECOVERABLE")
		var cost: int = int(step["cost"])
		if _kits < cost:
			return _reject("INSUFFICIENT_KITS")
		_kits -= cost
		_completed[str(step["id"])] = true
		_record("verified_" + str(step["kind"]))
		if _completed.size() == steps.size():
			_phase = "solved"
		return {"ok": true, "code": "CASE_SOLVED" if solved() else "CASE_STEP_VERIFIED",
			"completed": _completed.size(), "kits": _kits}
	return _reject("STEP_OR_DEPENDENCY_LOCKED")


func snapshot() -> Dictionary:
	return {"qualification": QUALIFICATION, "level_id": _spec.get("level_id", ""),
		"phase": _phase, "route": _route, "kits": _kits, "liabilities": _liabilities,
		"faults": _faults, "recoveries": _recoveries,
		"completed_steps": _completed.keys().duplicate(),
		"history": _history.duplicate(true)}
