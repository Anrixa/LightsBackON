extends RefCounted
## EXP015 A09 — authoritative cold-start commissioning at 25 original roots.
## The A09 original feeder and reserve ledger is the only mutation authority.
## Original root restoration and energization remain EXP04/host-owned.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Regional := preload("res://scripts/gameplay/expedition_regional_network.gd")

const BOOK_PATH: String = "res://scenes/expeditions/region_entries_exp015_a09.json"
const AUTHORITY: String = "EXP015_A09_ORIGINAL_ROOT_COMMISSIONING"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const RISK: Dictionary = {
	"depth": ["entry_flood_lockout", 2],
	"conductivity": ["entry_arc_clearance", 4],
	"mechanical": ["entry_manual_interlock", 2],
	"structure": ["entry_shoring_permit", 3],
	"weather": ["entry_weather_window", 3]
}
const ACTIONS: Array[String] = [
	"entry_survey", "entry_isolate", "entry_critical", "entry_transport",
	"entry_buffer", "entry_managed", "entry_unblock", "entry_verify",
	"entry_signoff"
]

var _recipe: Dictionary = {}
var _network: Regional
var _phase: String = "inactive"
var _first_route: String = ""
var _reserve_policy: String = ""
var _initial_reserve_pu: int = 0
var _initial_service_debt: int = 0
var _reserve_spent_pu: int = 0
var _regional_managed_pressure_pu: int = 0
var _events: Array[Dictionary] = []


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return data if data is Dictionary else {}


static func entry_for(book: Dictionary, site_id: String) -> Dictionary:
	for raw: Variant in book.get("entries", []):
		if raw is Dictionary and raw.get("entry_site_id") == site_id:
			return (raw as Dictionary).duplicate(true)
	return {}


## Strict 25-region source graph oracle. Five original EXP01 tasks per root,
## exact branch feeder IDs/capacities/protections and regional reserve/risk.
static func inspect(atlas: Dictionary, book: Dictionary,
		networks: Dictionary) -> Dictionary:
	if book.get("schema_version") != 1 or book.get("authority") != AUTHORITY or \
			book.get("predecessor") != "EXP015_A08" or \
			book.get("qualification") != QUALIFICATION or \
			book.get("legacy_campaign_contracts_unchanged") != true or \
			book.get("original_entries") != 25 or \
			not book.get("entries") is Array or book["entries"].size() != 25 or \
			not networks.get("regions") is Array or networks["regions"].size() != 25:
		return _fail("ENTRY_SOURCE_AUTHORITY")
	var seen: Dictionary = {}
	var risks: Dictionary = {}
	var index: int = 0
	for region: Dictionary in networks["regions"]:
		if not bool(Regional.inspect_region(atlas, region).get("ok", false)):
			return _fail("ENTRY_ORIGINAL_NETWORK_INVALID")
		var site: Dictionary = region["source_sites"][0]
		var first: Dictionary = region["source_sites"][1]
		var critical: Dictionary = region["source_sites"][2]
		var case: Dictionary = book["entries"][index]
		index += 1
		var root: String = str(site["site_id"])
		var original: Dictionary = Atlas.find_level(atlas, root)
		var task_ids: Array[String] = []
		for task: Dictionary in original.get("tasks", []):
			task_ids.append(str(task["id"]))
		var a: Dictionary = {}
		var b: Dictionary = {}
		for feeder: Dictionary in region["primary_feeders"]:
			if feeder["to"] == first["site_id"]:
				a = feeder
			if feeder["to"] == critical["site_id"]:
				b = feeder
		var risk: String = str(region["risk_class"])
		if original.is_empty() or a.is_empty() or b.is_empty() or \
				not RISK.has(risk) or seen.has(root) or \
				site["campaign_role"] != "entry" or \
				first["campaign_role"] != "first_route_a" or \
				critical["campaign_role"] != "first_route_b" or \
				a["from"] != root or b["from"] != root or \
				case.get("region_id") != region["region_id"] or \
				case.get("entry_site_id") != root or \
				case.get("location_id") != site["location_id"] or \
				case.get("worksite_family") != site["worksite_family"] or \
				case.get("original_task_ids") != task_ids or \
				case.get("transport_site_id") != first["site_id"] or \
				case.get("transport_feeder_id") != a["edge_id"] or \
				case.get("transport_protection") != a["protection"] or \
				case.get("transport_capacity_pu") != a["capacity_pu"] or \
				case.get("critical_site_id") != critical["site_id"] or \
				case.get("critical_feeder_id") != b["edge_id"] or \
				case.get("critical_protection") != b["protection"] or \
				case.get("critical_capacity_pu") != b["capacity_pu"] or \
				case.get("regional_critical_service_id") != region["critical_service_site"] or \
				case.get("risk_class") != risk or \
				case.get("entry_risk_proof") != RISK[risk][0] or \
				case.get("managed_pressure_pu") != RISK[risk][1] or \
				case.get("initial_reserve_pu") != region["initial_reserve_pu"] or \
				case.get("qualification") != QUALIFICATION:
			return _fail("ENTRY_ORIGINAL_SOURCE_MISMATCH")
		seen[root] = true
		risks[risk] = true
	if seen.size() != 25 or risks.size() != 5:
		return _fail("ENTRY_COVERAGE_OR_RISK_MISSING")
	return {"ok": true, "original_roots": seen.size(),
		"regional_risks": risks.size(), "original_first_feed_paths": 50}


func configure(recipe: Dictionary, network: Regional) -> Dictionary:
	if not _recipe.is_empty() or network == null:
		return _fail("ENTRY_MISSING_HOST_CONTEXT")
	var book: Dictionary = load_book()
	var check: Dictionary = inspect(Atlas.load_catalog(), book, Regional.load_book())
	if not bool(check.get("ok", false)):
		return check
	var pinned: Dictionary = entry_for(book, str(recipe.get("entry_site_id", "")))
	if pinned.is_empty() or pinned != recipe:
		return _fail("ENTRY_SOURCE_IDENTITY_MISMATCH")
	var state: Dictionary = network.snapshot()
	var site: String = str(pinned["entry_site_id"])
	if state.is_empty() or state.get("region_id") != pinned["region_id"] or \
			state.get("level_id") != site or \
			not state["feeders"].has(str(pinned["transport_feeder_id"])) or \
			not state["feeders"].has(str(pinned["critical_feeder_id"])):
		return _fail("ENTRY_ORIGINAL_DISPATCH_MISMATCH")
	_recipe = pinned.duplicate(true)
	_network = network
	_phase = "survey_pending"
	return {"ok": true, "original_root": site}


func definition_snapshot() -> Dictionary:
	return _recipe.duplicate(true)


## These precise network acts would bypass the A09 interlock and the original
## preparation/reserve decision if allowed through the generic A09 board path.
func protects_original_asset(action: String) -> bool:
	if _recipe.is_empty():
		return false
	if ["regional_buffer", "regional_managed", "regional_recharge"].has(action):
		return true
	var parts: PackedStringArray = action.split(":")
	return parts.size() >= 2 and \
		["regional_isolate", "regional_reset"].has(parts[0]) and \
		[str(_recipe["transport_feeder_id"]),
			str(_recipe["critical_feeder_id"])].has(parts[1])


func _source_valid() -> bool:
	if _recipe.is_empty() or _network == null or \
			_first_route.is_empty() or _reserve_policy.is_empty():
		return false
	var state: Dictionary = _network.snapshot()
	var root: String = str(_recipe["entry_site_id"])
	if state.get("level_id") != root or state.get("region_id") != _recipe["region_id"] or \
			bool(state["sites"][root]["restored"]) or \
			bool(state["sites"][root]["energized"]) or \
			bool(state["sites"][str(_recipe["transport_site_id"])]["energized"]) or \
			bool(state["sites"][str(_recipe["critical_site_id"])]["energized"]) or \
			not _network.site_prepared():
		return false
	for id: String in [str(_recipe["transport_feeder_id"]),
			str(_recipe["critical_feeder_id"])]:
		var feeder: Dictionary = state["feeders"][id]
		if bool(feeder["isolated"]) or str(feeder["fault"]) != "":
			return false
	if _reserve_policy == "finite_buffer":
		return _reserve_spent_pu == 2 and \
			int(state["reserve_pu"]) == _initial_reserve_pu - 2 and \
			int(_network.site_conditions()["service_debt"]) == _initial_service_debt
	if _reserve_policy == "managed_debt":
		return _reserve_spent_pu == 0 and \
			int(state["reserve_pu"]) == _initial_reserve_pu and \
			int(_network.site_conditions()["service_debt"]) == _initial_service_debt + 2
	return false


func closed() -> bool:
	return _phase == "signed_off" and _source_valid()


func snapshot() -> Dictionary:
	if _recipe.is_empty():
		return {}
	var network_state: Dictionary = _network.snapshot()
	var root: String = str(_recipe["entry_site_id"])
	return {"region_id": _recipe["region_id"], "entry_site_id": root,
		"phase": _phase, "preferred_branch": _first_route,
		"reserve_policy": _reserve_policy,
		"source_risk_protocol": _recipe["entry_risk_proof"],
		"initial_reserve_pu": _initial_reserve_pu,
		"reserve_spent_pu": _reserve_spent_pu,
		"managed_risk_pressure_pu": _regional_managed_pressure_pu,
		"live_regional_service_debt": _network.site_conditions()["service_debt"],
		"root_restoration_receipt": network_state["sites"][root]["restored"],
		"root_actually_energized": network_state["sites"][root]["energized"],
		"closed": closed(), "events": _events.duplicate(true),
		"qualification": QUALIFICATION}


func _record(action: String) -> void:
	_events.append({"sequence": _events.size() + 1, "action": action,
		"phase": _phase, "preferred_branch": _first_route,
		"reserve_policy": _reserve_policy})


func operate(action: String) -> Dictionary:
	if _recipe.is_empty():
		return _fail("ENTRY_NOT_CONFIGURED")
	if not ACTIONS.has(action) and \
			action != "entry_contain:" + str(_recipe["entry_risk_proof"]):
		return _fail("ENTRY_UNKNOWN_OR_FORGED_ACTION")
	var state: Dictionary = _network.snapshot()
	if state.get("level_id") != _recipe["entry_site_id"] or \
			state.get("region_id") != _recipe["region_id"]:
		return _fail("ENTRY_CHANGED_DISPATCH")
	var feeder_a: String = str(_recipe["transport_feeder_id"])
	var feeder_b: String = str(_recipe["critical_feeder_id"])
	var next: Dictionary = {}
	match action:
		"entry_survey":
			if _phase != "survey_pending" or \
					bool(state["sites"][str(_recipe["entry_site_id"])]["restored"]) or \
					bool(state["sites"][str(_recipe["entry_site_id"])]["energized"]) or \
					bool(state["feeders"][feeder_a]["isolated"]) or \
					bool(state["feeders"][feeder_b]["isolated"]) or \
					str(state["feeders"][feeder_a]["fault"]) != "" or \
					str(state["feeders"][feeder_b]["fault"]) != "" or \
					_network.site_prepared() or int(state["reserve_pu"]) < 2:
				return _fail("ENTRY_ORIGINAL_COLD_ROOT_REQUIRED")
			_initial_reserve_pu = int(state["reserve_pu"])
			_initial_service_debt = int(_network.site_conditions()["service_debt"])
			_phase = "lockout_pending"
		"entry_isolate":
			if _phase != "lockout_pending":
				return _fail("ENTRY_SURVEY_REQUIRED")
			next = _network.host_transition("isolate_feeder", feeder_a)
			if not bool(next.get("ok", false)):
				return next
			var second: Dictionary = _network.host_transition("isolate_feeder", feeder_b)
			if not bool(second.get("ok", false)):
				var rollback: Dictionary = _network.host_transition("reset_feeder", feeder_a)
				if not bool(rollback.get("ok", false)):
					return _fail("ENTRY_LOCKOUT_ROLLBACK_FAILED")
				return _fail("ENTRY_LOCKOUT_SECOND_FEEDER_DENIED")
			_phase = "branch_choice"
		"entry_critical", "entry_transport":
			if _phase != "branch_choice":
				return _fail("ENTRY_FIRST_BRANCH_CHOICE_REQUIRED")
			var preferred: String = feeder_b if action == "entry_critical" else feeder_a
			next = _network.host_transition("reset_feeder", preferred)
			if not bool(next.get("ok", false)):
				return next
			_first_route = "critical_health" if action == "entry_critical" else \
				"transport_access"
			_phase = "risk_proof"
		"entry_buffer":
			if _phase != "reserve_choice" or _network.site_prepared():
				return _fail("ENTRY_RISK_CLEARANCE_REQUIRED")
			# Legacy root preparation is zero-cost by design; the new exact
			# host-only A09 source commitment reserves 2 real PU first.
			next = _network.host_transition("commit_entry_buffer",
				str(_recipe["entry_site_id"]))
			if not bool(next.get("ok", false)):
				return next
			var planned: Dictionary = _network.prepare_site("buffer")
			if not bool(planned.get("ok", false)):
				return _fail("ENTRY_ATOMIC_BUFFER_PREPARATION_HOLD")
			var actual: int = _initial_reserve_pu - int(_network.snapshot()["reserve_pu"])
			if actual != 2:
				return _fail("ENTRY_BUFFER_ORIGINAL_RESERVE_MISMATCH")
			_reserve_spent_pu = actual
			_reserve_policy = "finite_buffer"
			_phase = "secondary_release"
		"entry_managed":
			if _phase != "reserve_choice" or _network.site_prepared():
				return _fail("ENTRY_RISK_CLEARANCE_REQUIRED")
			next = _network.host_transition("commit_entry_debt",
				str(_recipe["entry_site_id"]))
			if not bool(next.get("ok", false)):
				return next
			var planned: Dictionary = _network.prepare_site("managed")
			if not bool(planned.get("ok", false)):
				return _fail("ENTRY_ATOMIC_DEBT_PREPARATION_HOLD")
			_reserve_policy = "managed_debt"
			_regional_managed_pressure_pu = int(_recipe["managed_pressure_pu"])
			_phase = "secondary_release"
		"entry_unblock":
			if _phase != "secondary_release" or _first_route.is_empty():
				return _fail("ENTRY_RESERVE_DECISION_REQUIRED")
			var backup: String = feeder_a if _first_route == "critical_health" else feeder_b
			next = _network.host_transition("reset_feeder", backup)
			if not bool(next.get("ok", false)):
				return next
			_phase = "verification_pending"
		"entry_verify":
			if _phase != "verification_pending" or not _source_valid():
				return _fail("ENTRY_ACTUAL_A09_FEEDER_PROOF_REQUIRED")
			_phase = "verified"
		"entry_signoff":
			if _phase != "verified" or not _source_valid():
				return _fail("ENTRY_STABLE_NETWORK_REQUIRED")
			_phase = "signed_off"
		_:
			if _phase != "risk_proof" or \
					action != "entry_contain:" + str(_recipe["entry_risk_proof"]):
				return _fail("ENTRY_EXACT_SOURCE_RISK_PROOF_REQUIRED")
			_phase = "reserve_choice"
	_record(action)
	return {"ok": true, "snapshot": snapshot()}
