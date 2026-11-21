extends RefCounted
## EXP014 A09.2: experimental host-owned regional feeder and reserve state.
## Restorations are verified through EXP05's EXP04 receipt gate, never client data.
## No production saves, credits, RPCs, client clocks or legacy campaign changes.
##
## A09.3 attaches this service to the active mission and carries host decisions
## across dispatches; this module alone does not certify inter-session continuity.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Campaign := preload("res://scripts/progression/expedition_campaign.gd")

const BOOK_PATH: String = "res://scenes/expeditions/regional_networks_exp014_a09.json"
const SOURCE_AUTHORITY: String = "EXP014_A09_1_SOURCE_NETWORK_TOPOLOGIES_ONLY"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"

var _region: Dictionary = {}
var _site_id: String = ""
var _restored: Dictionary = {}
var _feeders: Dictionary = {}
var _ties: Dictionary = {}
var _isolated: Dictionary = {}
var _faulted: Dictionary = {}
var _engaged: Dictionary = {}
var _reserve: int = 0
var _initial_reserve: int = 0
var _recharged: bool = false
var _events: Array[Dictionary] = []
var _ready: bool = false


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return parsed if parsed is Dictionary else {}


static func entry_for(book: Dictionary, level_id: String) -> Dictionary:
	if not book.get("regions") is Array:
		return {}
	for candidate: Variant in book["regions"]:
		if not candidate is Dictionary or not candidate.get("source_sites") is Array:
			continue
		for site: Variant in candidate["source_sites"]:
			if site is Dictionary and site.get("site_id") == level_id:
				return candidate
	return {}


## Structural and identity audit is additive to the independent Python oracle.
## Keep a strict source/receipt boundary even when tests inject mutated books.
static func inspect_region(atlas: Dictionary, region: Dictionary) -> Dictionary:
	if region.is_empty() or not region.get("source_sites") is Array \
			or not region.get("primary_feeders") is Array or not region.get("standby_ties") is Array:
		return _fail("NETWORK_SOURCE_MISSING")
	var sites: Array = region["source_sites"]
	if sites.size() != 8 or region["primary_feeders"].size() != 7 \
			or region["standby_ties"].size() != 2:
		return _fail("NETWORK_CARDINALITY")
	var seen: Dictionary = {}
	for item: Variant in sites:
		if not item is Dictionary:
			return _fail("INVALID_SITE")
		var id: String = str(item.get("site_id", ""))
		var level: Dictionary = Atlas.find_level(atlas, id)
		if level.is_empty() or seen.has(id) or item.get("region_id", region.get("region_id")) != level.get("region_id") \
				or item.get("location_id") != level.get("location_id") \
				or level.get("region_id") != region.get("region_id"):
			return _fail("NETWORK_SITE_SOURCE_MISMATCH")
		var task_ids: Array = item.get("source_task_ids", [])
		if task_ids.size() != 5:
			return _fail("NETWORK_TASKS_MISSING")
		for index: int in range(5):
			if task_ids[index] != level["tasks"][index]["id"]:
				return _fail("NETWORK_TASK_SOURCE_MISMATCH")
		seen[id] = true
	if not seen.has(str(region.get("root_source_id", ""))) \
			or not seen.has(str(region.get("critical_service_site", ""))) \
			or not seen.has(str(region.get("reserve_anchor_site", ""))):
		return _fail("INVALID_NETWORK_ANCHOR")
	if int(region.get("initial_reserve_pu", 0)) < 1:
		return _fail("INVALID_RESERVE")
	var feeders: Dictionary = {}
	var incoming: Dictionary = {}
	for edge: Variant in region["primary_feeders"]:
		if not edge is Dictionary:
			return _fail("BAD_FEEDER")
		var key: String = str(edge.get("edge_id", ""))
		var source: String = str(edge.get("from", ""))
		var target: String = str(edge.get("to", ""))
		if key.is_empty() or feeders.has(key) or not seen.has(source) or not seen.has(target) \
				or source == target or incoming.has(target) or int(edge.get("capacity_pu", 0)) <= 0 \
				or edge.get("kind") != "protected_feeder" or edge.get("normally_closed") != true:
			return _fail("BAD_FEEDER")
		feeders[key] = true
		incoming[target] = source
	if incoming.has(str(region["root_source_id"])) or incoming.size() != 7:
		return _fail("BAD_PRIMARY_TREE")
	for site_id: String in seen:
		if site_id == str(region["root_source_id"]):
			continue
		var walker: String = site_id
		var path: Dictionary = {}
		while walker != str(region["root_source_id"]):
			if path.has(walker) or not incoming.has(walker):
				return _fail("CYCLIC_OR_DISCONNECTED_FEEDER")
			path[walker] = true
			walker = str(incoming[walker])
	var ties: Dictionary = {}
	for tie: Variant in region["standby_ties"]:
		if not tie is Dictionary:
			return _fail("BAD_STANDBY_TIE")
		var key: String = str(tie.get("edge_id", ""))
		if key.is_empty() or ties.has(key) or feeders.has(key) \
				or not seen.has(str(tie.get("from", ""))) or not seen.has(str(tie.get("to", ""))) \
				or tie.get("from") == tie.get("to") or int(tie.get("capacity_pu", 0)) < 2 \
				or tie.get("normally_closed") != false or tie.get("interlock") != "break_before_make":
			return _fail("BAD_STANDBY_TIE")
		ties[key] = true
	return {"ok": true, "sites": seen.size(), "primary_feeders": feeders.size(), "standby_ties": ties.size()}


func configure(atlas: Dictionary, profile: Dictionary, level_id: String,
		book: Dictionary = {}) -> Dictionary:
	if _ready:
		return _fail("ALREADY_CONFIGURED")
	var source: Dictionary = load_book() if book.is_empty() else book
	if source.get("schema_version") != 1 or source.get("authority") != SOURCE_AUTHORITY \
			or source.get("qualification") != QUALIFICATION or source.get("regions", []).size() != 25:
		return _fail("NETWORK_BOOK_AUTHORITY")
	var region: Dictionary = entry_for(source, level_id)
	var audit: Dictionary = inspect_region(atlas, region)
	if not bool(audit.get("ok", false)):
		return audit
	var board: Dictionary = Campaign.evaluate(profile, atlas, Campaign.load_routes())
	if not bool(board.get("ok", false)):
		return _fail("RESTORATION_RECEIPT_HOLD")
	var status: Dictionary = board["states"].get(level_id, {})
	if status.is_empty() or status.get("region_id") != region.get("region_id") \
			or status.get("status") == "LOCKED":
		return _fail("NETWORK_CAMPAIGN_LOCK")
	_region = region.duplicate(true)
	_site_id = level_id
	for edge: Dictionary in _region["primary_feeders"]:
		_feeders[str(edge["edge_id"])] = edge.duplicate(true)
	for tie: Dictionary in _region["standby_ties"]:
		_ties[str(tie["edge_id"])] = tie.duplicate(true)
	_initial_reserve = int(_region["initial_reserve_pu"])
	_reserve = _initial_reserve
	for site: Dictionary in _region["source_sites"]:
		var id: String = str(site["site_id"])
		if board["states"][id]["status"] == "RESTORED":
			_restored[id] = true
	_ready = true
	return {"ok": true, "region_id": _region["region_id"], "restored": _restored.size()}


## Only a host-loaded profile is admissible. Refresh is monotonic: revoked,
## missing or contradictory receipts never silently downgrade a live network.
func refresh_receipts(atlas: Dictionary, profile: Dictionary) -> Dictionary:
	if not _ready:
		return _fail("NOT_CONFIGURED")
	var board: Dictionary = Campaign.evaluate(profile, atlas, Campaign.load_routes())
	if not bool(board.get("ok", false)):
		return _fail("RESTORATION_RECEIPT_HOLD")
	var incoming: Dictionary = {}
	for site: Dictionary in _region["source_sites"]:
		var id: String = str(site["site_id"])
		if board["states"][id]["status"] == "RESTORED":
			incoming[id] = true
	for id: String in _restored:
		if not incoming.has(id):
			return _fail("RESTORATION_RECEIPT_ROLLBACK")
	_restored = incoming
	# Automatically open standby when the normal restored feeder is available.
	var normal: Dictionary = _live_nodes(false)
	for key: String in _engaged.keys():
		if normal.has(str(_ties[key]["to"])):
			_engaged.erase(key)
			_record("auto_open_duplicate_arrival", key)
	return {"ok": true, "restored": _restored.size()}


func _live_nodes(include_ties: bool) -> Dictionary:
	var energized: Dictionary = {}
	var root: String = str(_region.get("root_source_id", ""))
	if _restored.has(root):
		energized[root] = true
	for _pass: int in range(8):
		var changed: bool = false
		for key: String in _feeders:
			var edge: Dictionary = _feeders[key]
			var source: String = str(edge["from"])
			var target: String = str(edge["to"])
			if not _isolated.has(key) and energized.has(source) and _restored.has(target) \
					and not energized.has(target):
				energized[target] = true
				changed = true
		if include_ties:
			for key: String in _engaged:
				var tie: Dictionary = _ties[key]
				var source: String = str(tie["from"])
				var target: String = str(tie["to"])
				if energized.has(source) and _restored.has(target) and not energized.has(target):
					energized[target] = true
					changed = true
		if not changed:
			break
	return energized


func _record(action: String, edge: String) -> void:
	_events.append({"sequence": _events.size() + 1, "action": action, "asset": edge})


## Invoked only by trusted host-side code; never register a new RPC or trust
## arbitrary payload booleans for authorization.
func host_transition(action: String, asset: String, proof: String = "") -> Dictionary:
	if not _ready:
		return _fail("NOT_CONFIGURED")
	match action:
		"isolate_feeder":
			if not _feeders.has(asset):
				return _fail("UNKNOWN_FEEDER")
			if _isolated.has(asset):
				return _fail("ALREADY_ISOLATED")
			_isolated[asset] = true
		"trip_feeder":
			if not _feeders.has(asset) or proof != str(_region["fault_signature"]):
				return _fail("UNVERIFIED_REGION_FAULT")
			_isolated[asset] = true
			_faulted[asset] = proof
		"clear_fault":
			if not _faulted.has(asset) or proof != str(_region["recovery_procedure"]) \
					or not _restored.has(str(_region["root_source_id"])):
				return _fail("UNVERIFIED_RECOVERY")
			_faulted.erase(asset)
		"reset_feeder":
			if not _feeders.has(asset) or not _isolated.has(asset) or _faulted.has(asset):
				return _fail("FEEDER_RESET_DENIED")
			_isolated.erase(asset)
		"engage_tie":
			if not _ties.has(asset) or _engaged.has(asset):
				return _fail("TIE_UNAVAILABLE")
			var tie: Dictionary = _ties[asset]
			var live: Dictionary = _live_nodes(true)
			if not live.has(str(tie["from"])) or live.has(str(tie["to"])):
				return _fail("BREAK_BEFORE_MAKE_INTERLOCK")
			var cost: int = 2
			if cost > int(tie["capacity_pu"]) or cost > _reserve:
				return _fail("STANDBY_RESERVE_EXHAUSTED")
			_reserve -= cost
			_engaged[asset] = cost
		"release_tie":
			if not _engaged.has(asset):
				return _fail("TIE_NOT_ENGAGED")
			_engaged.erase(asset)
		"recharge_reserve":
			if asset != str(_region["reserve_anchor_site"]) or _recharged \
					or not _restored.has(asset) or not _engaged.is_empty():
				return _fail("RESERVE_RECHARGE_DENIED")
			_reserve = min(_initial_reserve, _reserve + maxi(2, _initial_reserve / 2))
			_recharged = true
		_:
			return _fail("UNKNOWN_NETWORK_OPERATION")
	_record(action, asset)
	return {"ok": true, "reserve": _reserve, "snapshot": snapshot()}


func snapshot() -> Dictionary:
	if not _ready:
		return {}
	var live: Dictionary = _live_nodes(true)
	var states: Dictionary = {}
	for site: Dictionary in _region["source_sites"]:
		var id: String = str(site["site_id"])
		var ready: bool = live.has(id)
		for key: String in _feeders:
			var feeder: Dictionary = _feeders[key]
			if feeder["to"] == id and not _isolated.has(key) and live.has(str(feeder["from"])):
				ready = true
		for key: String in _engaged:
			var tie: Dictionary = _ties[key]
			if tie["to"] == id and live.has(str(tie["from"])):
				ready = true
		states[id] = {"restored": _restored.has(id), "energized": live.has(id),
			"supply_ready": ready}
	var feeder_states: Dictionary = {}
	for key: String in _feeders:
		feeder_states[key] = {"isolated": _isolated.has(key),
			"fault": str(_faulted.get(key, "")), "from": _feeders[key]["from"],
			"to": _feeders[key]["to"], "capacity_pu": _feeders[key]["capacity_pu"]}
	var tie_states: Dictionary = {}
	for key: String in _ties:
		tie_states[key] = {"engaged": _engaged.has(key), "from": _ties[key]["from"],
			"to": _ties[key]["to"], "capacity_pu": _ties[key]["capacity_pu"]}
	return {"region_id": _region["region_id"], "level_id": _site_id,
		"source_risk": _region["risk_class"], "fault_signature": _region["fault_signature"],
		"recovery_procedure": _region["recovery_procedure"],
		"critical_service": _region["critical_service_site"],
		"shelter_service": _region["shelter_service_site"],
		"reserve_anchor": _region["reserve_anchor_site"],
		"reserve_pu": _reserve, "reserve_initial_pu": _initial_reserve,
		"sites": states, "feeders": feeder_states, "ties": tie_states,
		"events": _events.duplicate(true), "qualification": QUALIFICATION}
