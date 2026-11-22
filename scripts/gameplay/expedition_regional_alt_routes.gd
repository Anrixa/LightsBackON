extends RefCounted
## EXP015 A07: 100 ORIGINAL alternate-route incidents, four genuine mechanics.
## Original A09 feeder/tie/reserve/preparation authority; existing SessionHost
## board is the ONLY ingress. No invented power, new level, task, RPC or reward.

const Atlas := preload("res://scripts/world/dispatch_atlas.gd")
const Regional := preload("res://scripts/gameplay/expedition_regional_network.gd")

const BOOK_PATH: String = "res://scenes/expeditions/region_alt_routes_exp015_a07.json"
const AUTHORITY: String = "EXP015_A07_ORIGINAL_ALTERNATE_ROUTE_EMERGENCIES"
const QUALIFICATION: String = "SOURCE_HEADLESS_ONLY_HUMAN_CONTROLLER_RELEASE_HELD"
const ROLES: Array[String] = [
	"first_route_a", "first_route_b", "second_route_a", "second_route_b"
]
const RISK: Dictionary = {
	"depth": ["trenched_feeder_dewatering", 2],
	"conductivity": ["arc_free_critical_test", 4],
	"mechanical": ["interlock_return_proof", 2],
	"structure": ["shored_feeder_clearance", 3],
	"weather": ["span_exposure_recheck", 3]
}
const ACTIONS: Array[String] = [
	"route_survey", "route_trip", "route_rapid", "route_critical_priority",
	"route_managed", "route_buffer", "route_transfer", "route_prepare",
	"route_clear", "route_release", "route_reset", "route_verify", "route_signoff"
]

var _recipe: Dictionary = {}
var _network: Regional
var _phase: String = "inactive"
var _response: String = ""
var _original_supply_ready: bool = false
var _original_critical_live: bool = false
var _initial_available_reserve_pu: int = 0
var _reserve_spent_pu: int = 0
var _managed_pressure_pu: int = 0
var _events: Array[Dictionary] = []


static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}


static func load_book() -> Dictionary:
	if not FileAccess.file_exists(BOOK_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_PATH))
	return parsed if parsed is Dictionary else {}


static func entry_for(book: Dictionary, site_id: String) -> Dictionary:
	for raw: Variant in book.get("entries", []):
		if raw is Dictionary and raw.get("route_site_id") == site_id:
			return (raw as Dictionary).duplicate(true)
	return {}


## Every route asset must be an existing A09 regional feeder, original task,
## original standby tie (only the second-route-B sites), and exact source risk.
static func inspect(atlas: Dictionary, book: Dictionary,
		networks: Dictionary) -> Dictionary:
	if book.get("schema_version") != 1 or book.get("authority") != AUTHORITY or \
			book.get("predecessor") != "EXP015_A06" or \
			book.get("qualification") != QUALIFICATION or \
			book.get("legacy_campaign_contracts_unchanged") != true or \
			book.get("original_count") != 100 or \
			not book.get("entries") is Array or book["entries"].size() != 100 or \
			not networks.get("regions") is Array or networks["regions"].size() != 25:
		return _fail("ALT_SOURCE_AUTHORITY")
	var visited: Dictionary = {}
	var counts: Dictionary = {}
	for role: String in ROLES:
		counts[role] = 0
	var index: int = 0
	for region: Dictionary in networks["regions"]:
		if not bool(Regional.inspect_region(atlas, region).get("ok", false)):
			return _fail("ALT_ORIGINAL_NETWORK_MISMATCH")
		for slot: int in [1, 2, 4, 5]:
			var site: Dictionary = region["source_sites"][slot]
			var source_id: String = str(site["site_id"])
			var authored: Dictionary = book["entries"][index]
			index += 1
			var original: Dictionary = Atlas.find_level(atlas, source_id)
			var original_task_ids: Array[String] = []
			for task: Dictionary in original.get("tasks", []):
				original_task_ids.append(str(task["id"]))
			var feeder: Dictionary = {}
			for candidate: Dictionary in region["primary_feeders"]:
				if candidate["to"] == source_id:
					feeder = candidate
			var ties: Array[Dictionary] = []
			for candidate: Dictionary in region["standby_ties"]:
				if candidate["to"] == source_id:
					ties.append(candidate)
			var tie_id: String = str(ties[0]["edge_id"]) if ties.size() == 1 else ""
			var tie_from: String = str(ties[0]["from"]) if ties.size() == 1 else ""
			var risk: String = str(region["risk_class"])
			var role: String = str(site["campaign_role"])
			if original.is_empty() or feeder.is_empty() or not RISK.has(risk) or \
					visited.has(source_id) or not ROLES.has(role) or \
					ties.size() != (1 if role == "second_route_b" else 0) or \
					authored.get("region_id") != region["region_id"] or \
					authored.get("route_site_id") != source_id or \
					authored.get("location_id") != site["location_id"] or \
					authored.get("worksite_family") != site["worksite_family"] or \
					authored.get("campaign_role") != role or \
					authored.get("task_ids") != site["source_task_ids"] or \
					authored.get("task_ids") != original_task_ids or \
					authored.get("normal_feeder_id") != feeder["edge_id"] or \
					authored.get("upstream_site_id") != feeder["from"] or \
					authored.get("capacity_pu") != feeder["capacity_pu"] or \
					authored.get("original_protection") != feeder["protection"] or \
					authored.get("original_fault_signature") != region["fault_signature"] or \
					authored.get("original_recovery_procedure") != region["recovery_procedure"] or \
					authored.get("risk_class") != risk or \
					authored.get("risk_containment_protocol") != RISK[risk][0] or \
					authored.get("managed_outage_pressure_pu") != RISK[risk][1] or \
					authored.get("standby_tie_id") != tie_id or \
					authored.get("standby_source_site") != tie_from or \
					authored.get("initial_reserve_pu") != region["initial_reserve_pu"] or \
					authored.get("qualification") != QUALIFICATION:
				return _fail("ALT_ORIGINAL_ROUTE_BINDING")
			visited[source_id] = true
			counts[role] = int(counts[role]) + 1
	for role: String in ROLES:
		if int(counts[role]) != 25:
			return _fail("ALT_ROLE_COVERAGE")
	return {"ok": true, "original_sites": visited.size(), "role_counts": counts,
		"risk_protocols": RISK.size()}


func configure(recipe: Dictionary, network: Regional) -> Dictionary:
	if not _recipe.is_empty() or network == null:
		return _fail("ALT_ALREADY_CONFIGURED_OR_NO_NETWORK")
	var source: Dictionary = load_book()
	var audited: Dictionary = inspect(Atlas.load_catalog(), source, Regional.load_book())
	if not bool(audited.get("ok", false)):
		return audited
	var approved: Dictionary = entry_for(source, str(recipe.get("route_site_id", "")))
	if approved.is_empty() or approved != recipe:
		return _fail("ALT_UNPINNED_ROUTE")
	var state: Dictionary = network.snapshot()
	if state.is_empty() or state.get("level_id") != approved["route_site_id"] or \
			state.get("region_id") != approved["region_id"] or \
			not state["feeders"].has(str(approved["normal_feeder_id"])):
		return _fail("ALT_HOST_CONTEXT_MISMATCH")
	_recipe = approved.duplicate(true)
	_network = network
	_phase = "survey_pending"
	return {"ok": true, "role": _recipe["campaign_role"],
		"original_site": _recipe["route_site_id"]}


func definition_snapshot() -> Dictionary:
	return _recipe.duplicate(true)


## Protect ONLY the original active feeder and, if present, its real tie.
## This blocks direct host-board bypass of the source-verified fault sequence.
func protects_original_asset(action: String) -> bool:
	if _recipe.is_empty():
		return false
	var parts: PackedStringArray = action.split(":")
	if parts.size() < 2:
		return false
	if ["regional_isolate", "regional_reset"].has(parts[0]):
		return parts[1] == str(_recipe["normal_feeder_id"])
	if ["regional_engage", "regional_release"].has(parts[0]):
		return not str(_recipe["standby_tie_id"]).is_empty() and \
			parts[1] == str(_recipe["standby_tie_id"])
	return false


func _source_valid() -> bool:
	if _network == null or _recipe.is_empty():
		return false
	var state: Dictionary = _network.snapshot()
	if state.get("level_id") != _recipe["route_site_id"] or \
			state.get("region_id") != _recipe["region_id"]:
		return false
	var feeder: Dictionary = state["feeders"][str(_recipe["normal_feeder_id"])]
	if bool(feeder["isolated"]) or str(feeder["fault"]) != "":
		return false
	var tie_id: String = str(_recipe["standby_tie_id"])
	if not tie_id.is_empty() and bool(state["ties"][tie_id]["engaged"]):
		return false
	if str(_recipe["campaign_role"]).begins_with("second_") and \
			not _network.site_prepared():
		return false
	# A signoff does not conjure an EXP04 restoration receipt or a live site.
	return bool(state["sites"][str(_recipe["route_site_id"])]["supply_ready"]) == \
		_original_supply_ready


func closed() -> bool:
	return _phase == "signed_off" and _source_valid()


func snapshot() -> Dictionary:
	if _recipe.is_empty():
		return {}
	var state: Dictionary = _network.snapshot()
	return {"region_id": _recipe["region_id"],
		"route_site_id": _recipe["route_site_id"],
		"role": _recipe["campaign_role"],
		"source_protocol": _recipe["risk_containment_protocol"],
		"phase": _phase, "response": _response,
		"original_supply_ready": _original_supply_ready,
		"original_critical_energized": _original_critical_live,
		"site_now_supply_ready": bool(state["sites"][
			str(_recipe["route_site_id"])]["supply_ready"]),
		"site_has_restoration_receipt": bool(state["sites"][
			str(_recipe["route_site_id"])]["restored"]),
		"reserve_spent_pu": _reserve_spent_pu,
		"managed_pressure_pu": _managed_pressure_pu,
		"closed": closed(), "events": _events.duplicate(true),
		"qualification": QUALIFICATION}


func _record(action: String) -> void:
	_events.append({"sequence": _events.size() + 1, "action": action,
		"phase": _phase, "response": _response})


func operate(action: String) -> Dictionary:
	if _recipe.is_empty():
		return _fail("ALT_NOT_CONFIGURED")
	if not ACTIONS.has(action) and \
			action != "route_contain:" + str(_recipe["risk_containment_protocol"]):
		return _fail("ALT_UNKNOWN_ACTION_OR_RISK_PROTOCOL")
	var state: Dictionary = _network.snapshot()
	if state.get("level_id") != _recipe["route_site_id"] or \
			state.get("region_id") != _recipe["region_id"]:
		return _fail("ALT_DISPATCH_CHANGED")
	var role: String = str(_recipe["campaign_role"])
	var feeder: String = str(_recipe["normal_feeder_id"])
	var tie: String = str(_recipe["standby_tie_id"])
	var step: Dictionary = {}
	match action:
		"route_survey":
			if _phase != "survey_pending" or \
					bool(state["feeders"][feeder]["isolated"]) or \
					str(state["feeders"][feeder]["fault"]) != "":
				return _fail("ALT_SOURCE_SURVEY_DENIED")
			_original_supply_ready = bool(
				state["sites"][str(_recipe["route_site_id"])]["supply_ready"])
			_original_critical_live = bool(
				state["sites"][str(_recipe["route_site_id"])]["energized"])
			_initial_available_reserve_pu = int(state["reserve_pu"])
			_phase = "stress_pending"
		"route_trip":
			if _phase != "stress_pending":
				return _fail("ALT_SURVEY_REQUIRED")
			step = _network.host_transition("trip_feeder",
				feeder, str(_recipe["original_fault_signature"]))
			if not bool(step.get("ok", false)):
				return step
			_phase = "response_choice"
		"route_rapid":
			if _phase != "response_choice" or role != "first_route_a" or \
					not _original_supply_ready or int(_recipe["capacity_pu"]) < 16:
				return _fail("ALT_RAPID_NEEDS_REAL_UPSTREAM_CAPACITY")
			_response = "rapid_feeder_containment"
			_phase = "risk_proof_pending"
		"route_critical_priority":
			if _phase != "response_choice" or role != "first_route_b" or \
					not _original_supply_ready:
				return _fail("ALT_CRITICAL_PRIORITY_NEEDS_LIVE_UPSTREAM")
			_response = "upstream_critical_priority"
			_phase = "risk_proof_pending"
		"route_managed":
			if _phase != "response_choice":
				return _fail("ALT_SERVICE_CHOICE_REQUIRED")
			if role == "first_route_a" or role == "first_route_b":
				_managed_pressure_pu = int(_recipe["managed_outage_pressure_pu"])
				_response = "managed_first_route"
				_phase = "risk_proof_pending"
			elif role == "second_route_a":
				step = _network.prepare_site("managed")
				if not bool(step.get("ok", false)):
					return step
				_managed_pressure_pu = int(_recipe["managed_outage_pressure_pu"])
				_response = "managed_debt"
				_phase = "repair_pending"
			elif role == "second_route_b":
				if not tie.is_empty() and bool(state["ties"][tie]["engaged"]):
					return _fail("ALT_UNEXPECTED_STANDBY_ENGAGED")
				_managed_pressure_pu = int(_recipe["managed_outage_pressure_pu"])
				_response = "managed_outage"
				_phase = "preparation_pending"
		"route_buffer":
			if _phase != "response_choice" or role != "second_route_a":
				return _fail("ALT_BUFFER_ONLY_SECOND_A")
			var before: int = int(state["reserve_pu"])
			step = _network.prepare_site("buffer")
			if not bool(step.get("ok", false)):
				return step
			_reserve_spent_pu = before - int(_network.snapshot()["reserve_pu"])
			_response = "finite_reserve_buffer"
			_phase = "repair_pending"
		"route_transfer":
			if _phase != "response_choice" or role != "second_route_b" or \
					tie.is_empty():
				return _fail("ALT_TRANSFER_REQUIRES_ORIGINAL_TIE")
			var before: int = int(state["reserve_pu"])
			step = _network.host_transition("engage_tie", tie)
			if not bool(step.get("ok", false)):
				return step
			_reserve_spent_pu = before - int(_network.snapshot()["reserve_pu"])
			_response = "original_standby_transfer"
			_phase = "preparation_pending"
		"route_prepare":
			if _phase != "preparation_pending" or role != "second_route_b":
				return _fail("ALT_SECOND_B_PREPARATION_REQUIRED")
			step = _network.prepare_site("buffer" if _response == \
				"original_standby_transfer" else "managed")
			if not bool(step.get("ok", false)):
				return step
			_phase = "repair_pending"
		"route_clear":
			if _phase != "repair_pending":
				return _fail("ALT_REPAIR_NOT_READY")
			step = _network.host_transition("clear_fault",
				feeder, str(_recipe["original_recovery_procedure"]))
			if not bool(step.get("ok", false)):
				return step
			_phase = "tie_release" if role == "second_route_b" else "reset_pending"
		"route_release":
			if _phase != "tie_release" or role != "second_route_b":
				return _fail("ALT_RELEASE_NOT_READY")
			if _response == "original_standby_transfer":
				step = _network.host_transition("release_tie", tie)
				if not bool(step.get("ok", false)):
					return step
			elif bool(state["ties"][tie]["engaged"]):
				return _fail("ALT_UNEXPECTED_STANDBY_ENGAGED")
			_phase = "reset_pending"
		"route_reset":
			if _phase != "reset_pending":
				return _fail("ALT_RESET_NOT_READY")
			step = _network.host_transition("reset_feeder", feeder)
			if not bool(step.get("ok", false)):
				return step
			_phase = "verification_pending"
		"route_verify":
			if _phase != "verification_pending" or not _source_valid():
				return _fail("ALT_ACTUAL_NETWORK_PROOF_REQUIRED")
			_phase = "verified"
		"route_signoff":
			if _phase != "verified" or not _source_valid():
				return _fail("ALT_STABLE_ROUTE_REQUIRED")
			_phase = "signed_off"
		_:
			if action != "route_contain:" + str(_recipe["risk_containment_protocol"]) or \
					_phase != "risk_proof_pending" or \
					not role.begins_with("first_"):
				return _fail("ALT_ORIGINAL_RISK_CONTAINMENT_REQUIRED")
			_phase = "repair_pending"
	_record(action)
	return {"ok": true, "snapshot": snapshot()}
