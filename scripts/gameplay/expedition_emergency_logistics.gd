extends RefCounted
## EXP010 — Host-authoritative emergency supply dispatch for experimental expeditions.
##
## Every allocation, recall, delivery, recommission and certification runs through
## the existing SessionHost's validated, deduplicated, range/LoS-checked envelope.
## Only the host supplies the 10 Hz clock and the EXP08/EXP009 safety evidence.
## No production save, credited reward, or C01-C12 contract is modified.

const BOOK_PATH: String = "res://scenes/expeditions/emergency_logistics.json"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const ANCHORS: Array[String] = ["PANEL_WEST", "PANEL_SPUR", "R_WEST"]
const ROUTES: Dictionary = {
	"direct": {"spares": 2, "fuel": 1, "ticks": 6},
	"relay": {"spares": 1, "fuel": 2, "ticks": 14}
}
const CARGO: Dictionary = {
	"distribution": ["Grid reconnection sleeve", "Priority feeder stabilizer"],
	"transport": ["Crossing signal isolator", "Platform traction control pack"],
	"health": ["Cold-chain transfer cassette", "Sterile room safety module"],
	"commerce": ["Protected archive bus coupler", "Market emergency light kit"],
	"waterworks": ["Sluice backflow seal", "Flood pump emergency control"],
	"communications": ["Relay synchronization module", "Emergency antenna switchgear"],
	"education": ["Workshop circuit isolator", "Campus evacuation controller"],
	"shelter": ["Shelter heating link", "Emergency exit transfer assembly"]
}
const MAX_EVENTS: int = 24

var _spec: Dictionary = {}
var _jobs: Dictionary = {}
var _stock: Dictionary = {}
var _active: Dictionary = {}
var _manifest: bool = false
var _certified: bool = false
var _clock: int = 0
var _late: int = 0
var _recalls: int = 0
var _reopens: int = 0
var _history: Array[Dictionary] = []


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return decoded if decoded is Dictionary else {}


static func entry_for(book: Dictionary, level: Dictionary, chain: Dictionary) -> Dictionary:
	for raw: Variant in book.get("entries", []):
		if not raw is Dictionary:
			return {}
		var entry: Dictionary = raw
		if entry.get("level_id") != level.get("id"):
			continue
		for key: String in ["location_id", "source_puzzle_identity"]:
			var expected: Variant = level.get("location_id") if key == "location_id" else level.get("puzzle_identity")
			if entry.get(key) != expected:
				return {}
		for key: String in ["chain_key", "scenario_key", "site"]:
			if entry.get(key) != chain.get(key):
				return {}
		return entry.duplicate(true)
	return {}


## All 200 books must pin the authoritative EXP01 and EXP009 identities.
## Reject swapped/duplicate manifests, imported targets and material inflation.
static func inspect(atlas: Dictionary, consequences: Dictionary, book: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if book.get("schema_version") != 1 or book.get("authority") != "EXP010_HOST_LOGISTICS" or \
			book.get("atlas_revision") != atlas.get("revision"):
		errors.append("HEADER_INVALID")
	var entries: Variant = book.get("entries")
	if not entries is Array or (entries as Array).size() != 200:
		return {"ok": false, "code": "EXP010_COUNT_INVALID", "failures": errors}
	var levels: Dictionary = {}
	for level: Dictionary in atlas.get("levels", []):
		levels[str(level.get("id", ""))] = level
	var chains: Dictionary = {}
	for chain: Dictionary in consequences.get("entries", []):
		chains[str(chain.get("level_id", ""))] = chain
	var seen: Dictionary = {}
	var keys: Dictionary = {}
	var targets: Dictionary = {}
	var patterns: Dictionary = {}
	for i: int in range(200):
		if not entries[i] is Dictionary:
			errors.append("ENTRY_NOT_OBJECT")
			continue
		var entry: Dictionary = entries[i]
		var lid: String = str(entry.get("level_id", ""))
		if seen.has(lid) or not levels.has(lid) or not chains.has(lid):
			errors.append("LEVEL_INVALID_" + lid)
			continue
		seen[lid] = true
		if entry_for({"entries": [entry]}, levels[lid], chains[lid]).is_empty():
			errors.append("SOURCE_DRIFT_" + lid)
		var pattern: String = ["serial", "triage", "crossdock"][i % 3]
		if entry.get("pattern") != pattern:
			errors.append("PATTERN_DRIFT_" + lid)
		patterns[pattern] = true
		var key: String = str(chains[lid].get("chain_key", "")) + "|EXP010|" + pattern
		if entry.get("logistics_key") != key or keys.has(key):
			errors.append("KEY_INVALID_" + lid)
		keys[key] = true
		var suffix: String = lid.trim_prefix("LV_")
		var expected: Array[String] = ["LG_%s_DEPOT" % suffix, "LG_%s_CTRL" % suffix,
			"LG_%s_A" % suffix, "LG_%s_B" % suffix]
		var job_values: Variant = entry.get("jobs")
		if not job_values is Array or (job_values as Array).size() != 2:
			errors.append("JOB_COUNT_INVALID_" + lid)
			continue
		# Godot JSON parses numeric literals as floats; compare exact finite
		# quantities rather than numeric Variant/dictionary identity.
		var stock_valid: bool = false
		var stock_source: Variant = entry.get("stock")
		if stock_source is Dictionary:
			var stock: Dictionary = stock_source
			var spares: Variant = stock.get("spares")
			var fuel: Variant = stock.get("fuel")
			stock_valid = stock.size() == 2 and \
				(typeof(spares) == TYPE_INT or typeof(spares) == TYPE_FLOAT) and \
				(typeof(fuel) == TYPE_INT or typeof(fuel) == TYPE_FLOAT) and \
				float(spares) == 3.0 and float(fuel) == 3.0
		if entry.get("depot") != expected[0] or entry.get("console") != expected[1] or \
				entry.get("depot_anchor") != ANCHORS[0] or entry.get("console_anchor") != ANCHORS[2] or \
				not stock_valid:
			errors.append("DEPOT_OR_STOCK_INVALID_" + lid)
		for j: int in range(2):
			if not job_values[j] is Dictionary:
				errors.append("JOB_NOT_OBJECT_" + lid)
				continue
			var job: Dictionary = job_values[j]
			if job.get("id") != expected[j + 2] or job.get("anchor") != ANCHORS[j + 1] or \
					job.get("linked_service") != chains[lid]["nodes"][j + 1]["id"] or \
					job.get("requires") != (expected[2] if j == 1 and pattern == "serial" else "") or \
					job.get("priority") != ("critical" if j == 0 else "support") or \
					job.get("deadline_ticks") != (18 + i % 6 if j == 0 else 36 + i % 9) or \
					not CARGO.has(str(entry.get("site", ""))) or \
					job.get("cargo") != CARGO[str(entry["site"])][j]:
				errors.append("JOB_SOURCE_INVALID_" + lid)
		for id: String in expected:
			if targets.has(id):
				errors.append("TARGET_DUPLICATE_" + id)
			targets[id] = true
	if seen.size() != 200 or keys.size() != 200 or targets.size() != 800 or patterns.size() != 3:
		errors.append("COVERAGE_INVALID")
	return {"ok": errors.is_empty(), "code": "OK" if errors.is_empty() else "EXP010_INVALID",
		"levels": seen.size(), "jobs": seen.size() * 2,
		"targets": targets.size(), "patterns": patterns.size(), "failures": errors}


func configure(entry: Dictionary) -> Dictionary:
	if not _spec.is_empty() or not entry.has("logistics_key") or \
			not entry.get("jobs") is Array or (entry["jobs"] as Array).size() != 2:
		return {"ok": false, "code": "EXP010_CONFIG_INVALID"}
	_spec = entry.duplicate(true)
	_stock = entry["stock"].duplicate(true)
	for job: Dictionary in entry["jobs"]:
		_jobs[str(job["id"])] = {"status": "pending", "route": "", "late": false}
	return {"ok": true}


func definition_snapshot() -> Dictionary:
	return _spec.duplicate(true)


func target_ids() -> Array[String]:
	var ids: Array[String] = []
	if _spec.is_empty():
		return ids
	ids.append(str(_spec["depot"]))
	ids.append(str(_spec["console"]))
	for job: Dictionary in _spec["jobs"]:
		ids.append(str(job["id"]))
	return ids


func _job_def(id: String) -> Dictionary:
	for job: Dictionary in _spec.get("jobs", []):
		if job.get("id") == id:
			return job
	return {}


func _record(event: String, id: String) -> void:
	_history.append({"tick": _clock, "event": event, "target": id})
	while _history.size() > MAX_EVENTS:
		_history.pop_front()


func _host_ready(facts: Dictionary) -> bool:
	return bool(facts.get("consequences_solved", false)) and \
			bool(facts.get("faults_solved", false)) and \
			bool(facts.get("west_restored", false)) and \
			bool(facts.get("east_on", false)) and \
			not bool(facts.get("hazard_active", true))


func _all_delivered() -> bool:
	if _jobs.size() != 2:
		return false
	for status: Dictionary in _jobs.values():
		if status["status"] != "delivered":
			return false
	return true


func _can_dispatch(job: Dictionary, route: String) -> bool:
	if not _manifest or not _active.is_empty() or not _jobs.has(str(job.get("id", ""))) or \
			_jobs[str(job["id"])]["status"] != "pending":
		return false
	if job["requires"] != "" and _jobs[str(job["requires"])]["status"] != "delivered":
		return false
	# Crossdock contracts require the long relay on A before direct B:
	# the two routes cannot be exchanged arbitrarily on these sites.
	if _spec["pattern"] == "crossdock":
		if route != ("relay" if job["priority"] == "critical" else "direct"):
			return false
	var recipe: Dictionary = ROUTES[route]
	return int(_stock["spares"]) >= int(recipe["spares"]) and \
			int(_stock["fuel"]) >= int(recipe["fuel"])


## SessionHost-only operations. Payload contains one fixed action string, not
## player-supplied inventory, position, clock, route duration or outcome data.
func operate(id: String, action: String, facts: Dictionary) -> Dictionary:
	if _spec.is_empty():
		return {"ok": false, "code": "EXP010_NOT_CONFIGURED"}
	if not target_ids().has(id):
		return {"ok": false, "code": "EXP010_UNKNOWN_TARGET"}
	if id == str(_spec["console"]):
		if action != "certify":
			return {"ok": false, "code": "EXP010_CONSOLE_ACTION_INVALID"}
		if _certified:
			return {"ok": false, "code": "EXP010_ALREADY_CERTIFIED"}
		if not _manifest or not _active.is_empty() or not _all_delivered() or not _host_ready(facts):
			return {"ok": false, "code": "EXP010_LOGISTICS_INCOMPLETE"}
		_certified = true
		_record("LOGISTICS_CERTIFIED", id)
		return {"ok": true, "certified": true, "late": _late}
	if id == str(_spec["depot"]):
		if action == "manifest":
			if _manifest or not _host_ready(facts):
				return {"ok": false, "code": "EXP010_MANIFEST_INTERLOCK"}
			_manifest = true
			_record("MANIFEST_OPENED", id)
			return {"ok": true, "stock": _stock.duplicate(true)}
		if action == "recall":
			if _active.is_empty():
				return {"ok": false, "code": "EXP010_NOTHING_TO_RECALL"}
			var old_id: String = str(_active["job"])
			var recipe: Dictionary = ROUTES[str(_active["route"])]
			_stock["spares"] = int(_stock["spares"]) + int(recipe["spares"])
			_stock["fuel"] = int(_stock["fuel"]) + int(recipe["fuel"])
			_jobs[old_id] = {"status": "pending", "route": "", "late": false}
			_active.clear()
			_recalls += 1
			_record("SHIPMENT_RECALLED", old_id)
			return {"ok": true, "stock": _stock.duplicate(true)}
		var parts: PackedStringArray = action.split("_")
		if parts.size() != 3 or parts[0] != "dispatch" or \
				not ["a", "b"].has(parts[1]) or not ROUTES.has(parts[2]):
			return {"ok": false, "code": "EXP010_DEPOT_ACTION_INVALID"}
		if not _host_ready(facts):
			return {"ok": false, "code": "EXP010_HOST_UNSAFE"}
		var job_id: String = "LG_%s_%s" % [str(_spec["level_id"]).trim_prefix("LV_"),
			parts[1].to_upper()]
		var job: Dictionary = _job_def(job_id)
		if not _can_dispatch(job, parts[2]):
			return {"ok": false, "code": "EXP010_STOCK_OR_DEPENDENCY"}
		var recipe: Dictionary = ROUTES[parts[2]]
		_stock["spares"] = int(_stock["spares"]) - int(recipe["spares"])
		_stock["fuel"] = int(_stock["fuel"]) - int(recipe["fuel"])
		_active = {"job": job_id, "route": parts[2], "elapsed": 0,
			"duration": int(recipe["ticks"])}
		_jobs[job_id] = {"status": "transit", "route": parts[2], "late": false}
		_record("SHIPMENT_DISPATCHED_" + parts[2].to_upper(), job_id)
		return {"ok": true, "job": job_id, "remaining": _stock.duplicate(true)}
	if not _jobs.has(id):
		return {"ok": false, "code": "EXP010_UNKNOWN_JOB"}
	if not _host_ready(facts):
		return {"ok": false, "code": "EXP010_HOST_UNSAFE"}
	var status: String = str(_jobs[id]["status"])
	if action == "receive" and status == "arrived" and not _active.is_empty() and \
			str(_active["job"]) == id:
		var job: Dictionary = _job_def(id)
		if job["requires"] != "" and _jobs[str(job["requires"])]["status"] != "delivered":
			return {"ok": false, "code": "EXP010_DEPENDENCY_NOT_DELIVERED"}
		var is_late: bool = _clock > int(job["deadline_ticks"])
		_jobs[id]["status"] = "delivered"
		_jobs[id]["late"] = is_late
		if is_late:
			_late += 1
		_active.clear()
		_record("LATE_DELIVERY" if is_late else "ON_TIME_DELIVERY", id)
		return {"ok": true, "delivered": id, "late": is_late}
	if action == "recheck" and status == "recheck":
		_jobs[id]["status"] = "delivered"
		_record("SUPPLY_RECHECK", id)
		return {"ok": true, "delivered": id}
	return {"ok": false, "code": "EXP010_JOB_ACTION_INVALID"}


## Ten-Hz fixed host ticks: no progress under unsafe supply, and no mutation
## while dormant or safely certified. Unsafe post-certification supply reopens
## installed tasks for recheck without charging consumables again.
func advance(facts: Dictionary) -> void:
	if _spec.is_empty() or not _manifest:
		return
	if _certified:
		if _host_ready(facts):
			return
		_certified = false
		_reopens += 1
		_clock += 1
		for id: String in _jobs:
			if _jobs[id]["status"] == "delivered":
				_jobs[id]["status"] = "recheck"
		_record("SUPPLY_LOSS_REOPENED", str(_spec["console"]))
		return
	_clock += 1
	if _active.is_empty() or not _host_ready(facts):
		return
	var id: String = str(_active["job"])
	if _jobs[id]["status"] != "transit":
		return
	_active["elapsed"] = int(_active["elapsed"]) + 1
	if int(_active["elapsed"]) >= int(_active["duration"]):
		_jobs[id]["status"] = "arrived"
		_record("SHIPMENT_ARRIVED", id)


func solved() -> bool:
	return _certified and _all_delivered() and not _spec.is_empty()


func snapshot() -> Dictionary:
	return {"ok": not _spec.is_empty(), "level_id": _spec.get("level_id", ""),
		"logistics_key": _spec.get("logistics_key", ""),
		"manifest": _manifest, "certified": _certified, "solved": solved(),
		"tick": _clock, "stock": _stock.duplicate(true),
		"jobs": _jobs.duplicate(true), "active": _active.duplicate(true),
		"late": _late, "recalls": _recalls, "reopens": _reopens,
		"history": _history.duplicate(true), "qualification": QUALIFICATION}
